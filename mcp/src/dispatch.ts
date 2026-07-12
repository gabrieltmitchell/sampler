import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { createWriteStream, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { AnnotationHub } from "./http.js";
import type { SamplerStore } from "./store.js";
import type { AutoDispatchState, AutoDispatchStatus, StoredAnnotationWithSession } from "./types.js";

export interface SamplerDispatcherOptions {
  baseUrl: string;
  projectPath: string;
  store: SamplerStore;
  hub: AnnotationHub;
}

export class SamplerDispatcher {
  private isRunning = false;
  private rerunRequested = false;
  private unsubscribe?: () => void;
  private statusValue: AutoDispatchStatus;
  private activeChild?: ChildProcess;
  private ignoredChildren = new WeakSet<ChildProcess>();
  private activeAnnotationIds: string[] = [];
  private publishingInternalStatus = false;

  constructor(private readonly options: SamplerDispatcherOptions) {
    this.statusValue = makeStatus({
      enabled: true,
      state: "ready",
      healthy: true,
      project: options.projectPath,
      reason: null
    });
  }

  start(): void {
    const logCheck = ensureAgentLogsWritable(this.options.store);
    if (!logCheck.ok) {
      this.setStatus("logs_not_writable", false, logCheck.reason);
      console.error(`Sampler auto-dispatch: disabled (${logCheck.reason})`);
      console.error(`Recovery: mkdir -p "${agentLogsDir(this.options.store)}" && chmod u+w "${agentLogsDir(this.options.store)}"`);
      return;
    }

    const cursorAgentCheck = checkCursorAgent();
    if (!cursorAgentCheck.ok) {
      this.setStatus(cursorAgentCheck.state, false, cursorAgentCheck.reason, {
        lastOutput: cursorAgentCheck.output
      });
      console.error(`Sampler auto-dispatch: disabled (${cursorAgentCheck.reason})`);
      if (cursorAgentCheck.state === "invalid_cursor_config") {
        console.error("Fix .cursor/cli.json by removing unsupported keys, then restart sampler-mcp.");
      } else {
        console.error("Install the Cursor CLI or use sampler_watch_annotations from an active agent.");
      }
      return;
    }

    this.unsubscribe = this.options.hub.subscribe(() => this.dispatchIfNeeded());
    this.dispatchIfNeeded();
  }

  stop(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    this.stopActiveChild("auto-dispatch stopped");
    this.setStatus("disabled", true, "auto-dispatch stopped");
  }

  status(): AutoDispatchStatus {
    return {
      ...this.statusValue,
      lastLogEmpty: this.statusValue.lastLogPath ? this.statusValue.lastLogEmpty : null,
      activeAnnotationIds: this.activeAnnotationIds
    };
  }

  retry(): void {
    this.stopActiveChild("retry requested");
    this.rerunRequested = true;
    this.dispatchIfNeeded();
  }

  private dispatchIfNeeded(): void {
    if (this.publishingInternalStatus) {
      return;
    }

    const annotations = this.options.store.getDispatchCandidates();
    if (annotations.length === 0) {
      if (!this.isRunning && this.statusValue.state !== "disabled") {
        this.setStatus("ready", true, null);
      }
      return;
    }

    if (this.isRunning) {
      if (this.activeChild && this.isTerminalBlockedState()) {
        this.stopActiveChild(`replacing stale ${this.statusValue.state} dispatch`);
        this.rerunRequested = true;
        this.dispatchIfNeeded();
        return;
      }
      this.rerunRequested = true;
      if (!["agent_stalled", "agent_reconnecting", "agent_network_error", "last_run_failed"].includes(this.statusValue.state)) {
        this.setStatus("queued", true, `${annotations.length} annotation(s) queued while an agent is running`);
      }
      return;
    }

    this.isRunning = true;
    this.rerunRequested = false;
    this.spawnAgent(annotations);
  }

  private spawnAgent(annotations: StoredAnnotationWithSession[]): void {
    let logPath: string;
    try {
      logPath = this.createLogPath();
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      this.setStatus("logs_not_writable", false, reason);
      this.failAnnotations(annotations, "Agent logs are not writable.");
      this.finishRun();
      return;
    }

    const annotationIds = annotations.map((annotation) => annotation.id);
    this.activeAnnotationIds = annotationIds;
    const logStream = createWriteStream(logPath, { flags: "a" });
    const prompt = buildDispatchPrompt(this.options.baseUrl, annotations);
    const args = ["-p", prompt, "--output-format", "text"];
    this.setStatus("agent_starting", true, `Starting agent for ${annotations.length} annotation(s)`, {
      lastLogPath: logPath,
      lastLogEmpty: true,
      command: `cursor-agent ${args.map(shellQuote).join(" ")}`
    });
    for (const annotation of annotations) {
      this.options.store.updateStatusAndProgress(annotation.id, "acknowledged", "Starting agent...");
    }
    this.notifyHub();

    const child = spawn("cursor-agent", args, {
      cwd: this.options.projectPath,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"]
    });
    this.activeChild = child;

    this.setStatus("agent_started", true, "Agent process started", { pid: child.pid ?? null });
    console.error(`Sampler auto-dispatch started in ${this.options.projectPath}`);
    console.error(`Sampler auto-dispatch log: ${logPath}`);

    let sawOutput = false;
    let outputBuffer = "";
    const markOutput = (chunk: Buffer) => {
      sawOutput = true;
      const output = chunk.toString("utf8");
      outputBuffer = (outputBuffer + output).slice(-8000);
      const retryCount = extractRetryCount(outputBuffer);
      if (isReconnectOutput(outputBuffer)) {
        this.setStatus("agent_reconnecting", true, "Agent reconnecting to Cursor service", {
          lastLogEmpty: false,
          lastOutput: tailLine(outputBuffer),
          retryCount
        });
        this.options.store.updateProgressForAnnotations(annotationIds, retryCount ? `Agent reconnecting... retry ${retryCount}` : "Agent reconnecting...");
        this.notifyHub();
        return;
      }
      this.setStatus("running", true, "Agent produced output", {
        lastLogEmpty: false,
        lastOutput: tailLine(outputBuffer),
        retryCount
      });
    };
    child.stdout.on("data", markOutput);
    child.stderr.on("data", markOutput);
    child.stdout.pipe(logStream, { end: false });
    child.stderr.pipe(logStream, { end: false });

    // cursor-agent in --print text mode is usually silent until it finishes,
    // so stdout silence alone is not evidence of a stall. Annotation PATCHes
    // from the agent (progress/status updates) count as liveness. Only kill
    // after a long window with neither output nor annotation activity.
    const softStallMs = envTimeoutMs("SAMPLER_DISPATCH_SOFT_STALL_MS", 20_000);
    const hardStallMs = envTimeoutMs("SAMPLER_DISPATCH_HARD_STALL_MS", 300_000);
    const spawnedAt = Date.now();
    let softStallNotified = false;
    let sawAnnotationActivity = false;

    const hasAnnotationActivity = (): boolean => {
      const statuses = this.options.store.getStatusesByIds(annotationIds);
      return statuses.some((status) =>
        status.status === "resolved"
        || status.status === "dismissed"
        || (status.progress !== null && !isServerProgress(status.progress))
      );
    };

    const livenessInterval = setInterval(() => {
      if (!this.isRunning || this.activeChild !== child) {
        clearInterval(livenessInterval);
        return;
      }

      if (hasAnnotationActivity()) {
        if (!sawAnnotationActivity) {
          sawAnnotationActivity = true;
          this.setStatus("running", true, "Agent is reporting progress on annotations", {
            lastLogEmpty: !sawOutput
          });
        }
        return;
      }

      if (sawOutput || sawAnnotationActivity) {
        return;
      }

      const elapsed = Date.now() - spawnedAt;
      if (elapsed >= hardStallMs) {
        clearInterval(livenessInterval);
        this.setStatus("agent_stalled", false, "Agent started but has not responded", {
          lastLogPath: logPath,
          lastLogEmpty: true
        });
        this.options.store.updateProgressForAnnotations(annotationIds, "Agent started but has not responded.");
        this.stopActiveChild("agent produced no output or progress before hard stall timeout");
        this.notifyHub();
        if (this.rerunRequested) {
          this.dispatchIfNeeded();
        }
      } else if (elapsed >= softStallMs && !softStallNotified) {
        softStallNotified = true;
        this.setStatus("agent_started", true, "Agent is working; no output yet (normal while editing and building)", {
          lastLogPath: logPath,
          lastLogEmpty: true
        });
        this.options.store.updateProgressForAnnotations(annotationIds, "Agent is working...");
        this.notifyHub();
      }
    }, 5_000);

    const reconnectTimeout = setTimeout(() => {
      if (this.isRunning && this.activeChild === child && this.statusValue.state === "agent_reconnecting") {
        this.setStatus("agent_network_error", false, "Agent is still reconnecting to Cursor service", {
          lastLogPath: logPath,
          lastLogEmpty: false,
          lastOutput: tailLine(outputBuffer),
          retryCount: extractRetryCount(outputBuffer)
        });
        this.options.store.updateProgressForAnnotations(annotationIds, "Agent network connection failed.");
        this.stopActiveChild("agent reconnect timed out");
        this.notifyHub();
        if (this.rerunRequested) {
          this.dispatchIfNeeded();
        }
      }
    }, 60_000);

    child.once("error", (error) => {
      clearInterval(livenessInterval);
      clearTimeout(reconnectTimeout);
      logStream.write(`\nSampler auto-dispatch failed to start: ${error.message}\n`);
      logStream.end();
      this.setStatus("last_run_failed", false, error.message, { lastLogPath: logPath, lastLogEmpty: !sawOutput });
      this.failAnnotations(annotations, "Agent failed to start.");
      this.finishRun();
    });

    child.once("close", (code, signal) => {
      clearInterval(livenessInterval);
      clearTimeout(reconnectTimeout);
      logStream.write(`\nSampler auto-dispatch exited with code=${code ?? "null"} signal=${signal ?? "null"}\n`);
      logStream.end();
      if (this.ignoredChildren.has(child)) {
        return;
      }
      if (this.activeChild === child) {
        this.activeChild = undefined;
      }
      const authError = outputBuffer.includes("Authentication required") || outputBuffer.includes("agent login");
      const networkError = isReconnectOutput(outputBuffer);
      if (authError) {
        this.setStatus("auth_required", false, "Cursor CLI login required. Run cursor-agent login.", {
          lastLogPath: logPath,
          lastLogEmpty: !sawOutput,
          lastOutput: tailLine(outputBuffer),
          retryCount: extractRetryCount(outputBuffer)
        });
        this.failAnnotations(annotations, "Cursor CLI login required.");
      } else if (networkError && code !== 0) {
        this.setStatus("agent_network_error", false, "Agent lost connection to Cursor service", {
          lastLogPath: logPath,
          lastLogEmpty: !sawOutput,
          lastOutput: tailLine(outputBuffer),
          retryCount: extractRetryCount(outputBuffer)
        });
        this.failAnnotations(annotations, "Agent network connection failed.");
      } else if (code === 0) {
        this.setStatus("agent_completed", true, "Agent run completed", {
          lastLogPath: logPath,
          lastLogEmpty: !sawOutput,
          lastOutput: tailLine(outputBuffer),
          retryCount: extractRetryCount(outputBuffer)
        });
      } else {
        this.setStatus("last_run_failed", false, `Agent exited with code=${code ?? "null"} signal=${signal ?? "null"}`, {
          lastLogPath: logPath,
          lastLogEmpty: !sawOutput,
          lastOutput: tailLine(outputBuffer),
          retryCount: extractRetryCount(outputBuffer)
        });
        this.failAnnotations(annotations, "Agent failed. See dispatch log.");
      }
      this.finishRun();
    });
  }

  private finishRun(): void {
    this.isRunning = false;
    this.activeChild = undefined;
    this.activeAnnotationIds = [];
    if (this.rerunRequested && this.options.store.getDispatchCandidates().length > 0) {
      this.dispatchIfNeeded();
    }
  }

  private stopActiveChild(reason: string): void {
    const child = this.activeChild;
    this.isRunning = false;
    this.activeChild = undefined;
    this.activeAnnotationIds = [];

    if (!child || child.exitCode !== null || child.signalCode !== null) {
      return;
    }

    this.ignoredChildren.add(child);
    console.error(`Sampler auto-dispatch stopping pid ${child.pid ?? "unknown"}: ${reason}`);
    child.kill("SIGTERM");
    setTimeout(() => {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill("SIGKILL");
      }
    }, 3000);
  }

  private isTerminalBlockedState(): boolean {
    return this.statusValue.state === "agent_stalled"
      || this.statusValue.state === "agent_network_error"
      || this.statusValue.state === "last_run_failed"
      || this.statusValue.state === "auth_required";
  }

  private failAnnotations(annotations: StoredAnnotationWithSession[], progress: string): void {
    this.options.store.updateProgressForAnnotations(annotations.map((annotation) => annotation.id), progress);
    this.notifyHub();
  }

  private notifyHub(): void {
    this.publishingInternalStatus = true;
    try {
      this.options.hub.notify();
    } finally {
      this.publishingInternalStatus = false;
    }
  }

  private createLogPath(): string {
    const logsDir = agentLogsDir(this.options.store);
    mkdirSync(logsDir, { recursive: true });
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    return join(logsDir, `${stamp}.log`);
  }

  private setStatus(
    state: AutoDispatchState,
    healthy: boolean,
    reason: string | null,
    updates: Partial<AutoDispatchStatus> = {}
  ): void {
    this.statusValue = {
      ...this.statusValue,
      state,
      healthy,
      reason,
      lastError: healthy ? null : reason,
      updatedAt: new Date().toISOString(),
      ...updates
    };
  }
}

export function isCursorAgentAvailable(): boolean {
  return checkCursorAgent().ok;
}

export function checkCursorAgent():
  | { ok: true }
  | { ok: false; state: "missing_cursor_agent" | "invalid_cursor_config" | "last_run_failed"; reason: string; output: string | null } {
  const pathResult = spawnSync("sh", ["-lc", "command -v cursor-agent"], { encoding: "utf8", timeout: 3000 });
  if (!pathResult.stdout.trim()) {
    return {
      ok: false,
      state: "missing_cursor_agent",
      reason: pathResult.stderr.trim() || "cursor-agent was not found on PATH",
      output: null
    };
  }

  const result = spawnSync("cursor-agent", ["--version"], { encoding: "utf8", timeout: 5000 });
  const output = `${result.stdout}${result.stderr}`.trim();
  if (result.status === 0) {
    return { ok: true };
  }

  if (isInvalidCursorConfigOutput(output)) {
    return {
      ok: false,
      state: "invalid_cursor_config",
      reason: cursorConfigReason(output),
      output
    };
  }

  return {
    ok: false,
    state: "last_run_failed",
    reason: output || `cursor-agent --version exited with ${result.status ?? "unknown"}`,
    output
  };
}

export function agentLogsDir(store: SamplerStore): string {
  return join(store.rootDir, "agent-logs");
}

export function ensureAgentLogsWritable(store: SamplerStore): { ok: true } | { ok: false; reason: string } {
  const logsDir = agentLogsDir(store);
  const testPath = join(logsDir, ".write-test");
  try {
    mkdirSync(logsDir, { recursive: true });
    writeFileSync(testPath, "ok");
    rmSync(testPath, { force: true });
    return { ok: true };
  } catch (error) {
    return { ok: false, reason: error instanceof Error ? error.message : String(error) };
  }
}

function makeStatus(input: {
  enabled: boolean;
  state: AutoDispatchState;
  healthy: boolean;
  project: string | null;
  reason: string | null;
}): AutoDispatchStatus {
  return {
    enabled: input.enabled,
    state: input.state,
    healthy: input.healthy,
    project: input.project,
    reason: input.reason,
    lastError: input.healthy ? null : input.reason,
    lastLogPath: null,
    lastLogEmpty: null,
    lastOutput: null,
    retryCount: null,
    pid: null,
    command: null,
    activeAnnotationIds: [],
    updatedAt: new Date().toISOString()
  };
}

function buildDispatchPrompt(baseUrl: string, annotations: StoredAnnotationWithSession[]): string {
  const summary = annotations.map((annotation) => ({
    id: annotation.id,
    sessionId: annotation.sessionId,
    number: annotation.number,
    comment: annotation.comment,
    screenshotPath: annotation.screenshotPath,
    annotatedPath: annotation.annotatedPath
  }));

  return `You are handling Sampler iOS visual feedback annotations for the app in this repository.

Use the local Sampler HTTP API at ${baseUrl}. Do not wait for the user before acting.

Target annotations:
${JSON.stringify(summary, null, 2)}

Workflow:
1. For each target annotation, PATCH ${baseUrl}/annotations/<id> with {"status":"acknowledged","progress":"Making code changes..."}.
3. Inspect the annotation comment and the screenshot/annotated image paths from the response. Use the annotated image to identify the requested UI change.
4. Make the smallest code change that satisfies the annotation.
5. Before building, PATCH progress to "Rebuilding app...".
6. Build and reinstall/relaunch the app on the booted iOS Simulator using the project's normal build workflow, xcodebuild, and xcrun simctl where appropriate.
7. When the fix is complete and the app has been rebuilt/relaunched, PATCH ${baseUrl}/annotations/<id> with {"status":"resolved","progress":"Done","resolution":"<short summary>"}.
8. If you cannot safely make the change, PATCH ${baseUrl}/annotations/<id> with {"status":"dismissed","progress":"Needs manual review","resolution":"<short reason>"}.

Keep the resolution short because it is shown inside the iOS widget toast.`;
}

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function envTimeoutMs(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

const SERVER_PROGRESS_VALUES = new Set([
  "Starting agent...",
  "Agent is working...",
  "Agent started but has not responded.",
  "Agent network connection failed.",
  "Cursor CLI login required.",
  "Agent failed to start.",
  "Agent failed. See dispatch log.",
  "Agent logs are not writable."
]);

function isServerProgress(progress: string): boolean {
  return SERVER_PROGRESS_VALUES.has(progress) || progress.startsWith("Agent reconnecting...");
}

function isReconnectOutput(output: string): boolean {
  const normalized = output.toLowerCase();
  return normalized.includes("connection lost")
    || normalized.includes("reconnecting")
    || normalized.includes("retry attempt")
    || normalized.includes("agentn.global.api5.cursor.sh");
}

export function isInvalidCursorConfigOutput(output: string): boolean {
  const normalized = output.toLowerCase();
  return normalized.includes("unrecognized key")
    && (normalized.includes(".cursor/cli.json") || normalized.includes("cli.json"));
}

export function cursorConfigReason(output: string): string {
  const keys = output.match(/Unrecognized key\(s\):\s*([^\n]+)/i)?.[1]?.trim();
  return keys
    ? `.cursor/cli.json has unsupported key(s): ${keys}`
    : ".cursor/cli.json has unsupported keys";
}

function extractRetryCount(output: string): number | null {
  const matches = [...output.matchAll(/retry attempt\s+(\d+)/gi)];
  const latest = matches.at(-1)?.[1];
  return latest ? Number.parseInt(latest, 10) : null;
}

function tailLine(output: string): string | null {
  const lines = output
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  return lines.at(-1) ?? null;
}
