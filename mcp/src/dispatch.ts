import { spawn, spawnSync } from "node:child_process";
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

    if (!isCursorAgentAvailable()) {
      this.setStatus("missing_cursor_agent", false, "cursor-agent was not found on PATH");
      console.error("Sampler auto-dispatch: disabled (cursor-agent was not found on PATH)");
      console.error("Install the Cursor CLI or use sampler_watch_annotations from an active agent.");
      return;
    }

    this.unsubscribe = this.options.hub.subscribe(() => this.dispatchIfNeeded());
    this.dispatchIfNeeded();
  }

  stop(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    this.setStatus("disabled", true, "auto-dispatch stopped");
  }

  status(): AutoDispatchStatus {
    return {
      ...this.statusValue,
      lastLogEmpty: this.statusValue.lastLogPath ? this.statusValue.lastLogEmpty : null
    };
  }

  retry(): void {
    this.rerunRequested = true;
    this.dispatchIfNeeded();
  }

  private dispatchIfNeeded(): void {
    const annotations = this.options.store.getDispatchCandidates();
    if (annotations.length === 0) {
      if (!this.isRunning && this.statusValue.state !== "disabled") {
        this.setStatus("ready", true, null);
      }
      return;
    }

    if (this.isRunning) {
      this.rerunRequested = true;
      if (this.statusValue.state !== "agent_stalled" && this.statusValue.state !== "last_run_failed") {
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
    for (const annotation of annotations) {
      this.options.store.updateStatusAndProgress(annotation.id, "acknowledged", "Starting agent...");
    }
    this.options.hub.notify();

    const logStream = createWriteStream(logPath, { flags: "a" });
    const prompt = buildDispatchPrompt(this.options.baseUrl, annotations);
    const args = ["-p", prompt, "--output-format", "text"];
    this.setStatus("agent_starting", true, `Starting agent for ${annotations.length} annotation(s)`, {
      lastLogPath: logPath,
      lastLogEmpty: true,
      command: `cursor-agent ${args.map(shellQuote).join(" ")}`
    });

    const child = spawn("cursor-agent", args, {
      cwd: this.options.projectPath,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"]
    });

    this.setStatus("agent_started", true, "Agent process started", { pid: child.pid ?? null });
    console.error(`Sampler auto-dispatch started in ${this.options.projectPath}`);
    console.error(`Sampler auto-dispatch log: ${logPath}`);

    let sawOutput = false;
    let outputBuffer = "";
    const markOutput = (chunk: Buffer) => {
      sawOutput = true;
      this.setStatus("running", true, "Agent produced output", { lastLogEmpty: false });
      outputBuffer = (outputBuffer + chunk.toString("utf8")).slice(-8000);
    };
    child.stdout.on("data", markOutput);
    child.stderr.on("data", markOutput);
    child.stdout.pipe(logStream);
    child.stderr.pipe(logStream);

    const stallTimeout = setTimeout(() => {
      if (this.isRunning && !sawOutput) {
        this.setStatus("agent_stalled", false, "Agent started but has not responded", {
          lastLogPath: logPath,
          lastLogEmpty: true
        });
        this.options.store.updateProgressForAnnotations(annotationIds, "Agent started but has not responded.");
        this.options.hub.notify();
      }
    }, 15_000);

    child.once("error", (error) => {
      clearTimeout(stallTimeout);
      logStream.write(`\nSampler auto-dispatch failed to start: ${error.message}\n`);
      logStream.end();
      this.setStatus("last_run_failed", false, error.message, { lastLogPath: logPath, lastLogEmpty: !sawOutput });
      this.failAnnotations(annotations, "Agent failed to start.");
      this.finishRun();
    });

    child.once("close", (code, signal) => {
      clearTimeout(stallTimeout);
      logStream.write(`\nSampler auto-dispatch exited with code=${code ?? "null"} signal=${signal ?? "null"}\n`);
      logStream.end();
      const authError = outputBuffer.includes("Authentication required") || outputBuffer.includes("agent login");
      if (authError) {
        this.setStatus("auth_required", false, "Cursor CLI login required. Run cursor-agent login.", {
          lastLogPath: logPath,
          lastLogEmpty: !sawOutput
        });
        this.failAnnotations(annotations, "Cursor CLI login required.");
      } else if (code === 0) {
        this.setStatus("agent_completed", true, "Agent run completed", {
          lastLogPath: logPath,
          lastLogEmpty: !sawOutput
        });
      } else {
        this.setStatus("last_run_failed", false, `Agent exited with code=${code ?? "null"} signal=${signal ?? "null"}`, {
          lastLogPath: logPath,
          lastLogEmpty: !sawOutput
        });
        this.failAnnotations(annotations, "Agent failed. See dispatch log.");
      }
      this.finishRun();
    });
  }

  private finishRun(): void {
    this.isRunning = false;
    if (this.rerunRequested && this.options.store.getDispatchCandidates().length > 0) {
      this.dispatchIfNeeded();
    }
  }

  private failAnnotations(annotations: StoredAnnotationWithSession[], progress: string): void {
    this.options.store.updateProgressForAnnotations(annotations.map((annotation) => annotation.id), progress);
    this.options.hub.notify();
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
  const result = spawnSync("cursor-agent", ["--version"], { stdio: "ignore" });
  return result.status === 0;
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
    pid: null,
    command: null,
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
