import { spawn, spawnSync } from "node:child_process";
import { createWriteStream, mkdirSync } from "node:fs";
import { join } from "node:path";
import type { AnnotationHub } from "./http.js";
import type { SamplerStore } from "./store.js";

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

  constructor(private readonly options: SamplerDispatcherOptions) {}

  start(): void {
    this.unsubscribe = this.options.hub.subscribe(() => this.dispatchIfNeeded());
    this.dispatchIfNeeded();
  }

  stop(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }

  private dispatchIfNeeded(): void {
    if (!hasPendingAnnotations(this.options.store)) {
      return;
    }

    if (this.isRunning) {
      this.rerunRequested = true;
      return;
    }

    if (!isCursorAgentAvailable()) {
      console.error("Sampler auto-dispatch skipped: cursor-agent was not found on PATH.");
      console.error("Install the Cursor CLI or use sampler_watch_annotations from an active agent.");
      return;
    }

    this.isRunning = true;
    this.rerunRequested = false;
    this.spawnAgent();
  }

  private spawnAgent(): void {
    const logPath = this.createLogPath();
    const logStream = createWriteStream(logPath, { flags: "a" });
    const prompt = buildDispatchPrompt(this.options.baseUrl);
    const child = spawn("cursor-agent", ["-p", prompt, "--output-format", "text"], {
      cwd: this.options.projectPath,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"]
    });

    console.error(`Sampler auto-dispatch started in ${this.options.projectPath}`);
    console.error(`Sampler auto-dispatch log: ${logPath}`);

    child.stdout.pipe(logStream);
    child.stderr.pipe(logStream);

    child.once("error", (error) => {
      logStream.write(`\nSampler auto-dispatch failed to start: ${error.message}\n`);
      logStream.end();
      this.finishRun();
    });

    child.once("close", (code, signal) => {
      logStream.write(`\nSampler auto-dispatch exited with code=${code ?? "null"} signal=${signal ?? "null"}\n`);
      logStream.end();
      this.finishRun();
    });
  }

  private finishRun(): void {
    this.isRunning = false;
    if (this.rerunRequested && hasPendingAnnotations(this.options.store)) {
      this.dispatchIfNeeded();
    }
  }

  private createLogPath(): string {
    const logsDir = join(this.options.store.rootDir, "agent-logs");
    mkdirSync(logsDir, { recursive: true });
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    return join(logsDir, `${stamp}.log`);
  }
}

export function isCursorAgentAvailable(): boolean {
  const result = spawnSync("cursor-agent", ["--version"], { stdio: "ignore" });
  return result.status === 0;
}

function hasPendingAnnotations(store: SamplerStore): boolean {
  return store.getPending().some((annotation) => annotation.status === "pending");
}

function buildDispatchPrompt(baseUrl: string): string {
  return `You are handling Sampler iOS visual feedback annotations for the app in this repository.

Use the local Sampler HTTP API at ${baseUrl}. Do not wait for the user before acting.

Workflow:
1. Fetch pending annotations with: GET ${baseUrl}/pending
2. For each pending annotation, immediately PATCH ${baseUrl}/annotations/<id> with {"status":"acknowledged","progress":"Making code changes..."}.
3. Inspect the annotation comment and the screenshot/annotated image paths from the response. Use the annotated image to identify the requested UI change.
4. Make the smallest code change that satisfies the annotation.
5. Before building, PATCH progress to "Rebuilding app...".
6. Build and reinstall/relaunch the app on the booted iOS Simulator using the project's normal build workflow, xcodebuild, and xcrun simctl where appropriate.
7. When the fix is complete and the app has been rebuilt/relaunched, PATCH ${baseUrl}/annotations/<id> with {"status":"resolved","progress":"Done","resolution":"<short summary>"}.
8. If you cannot safely make the change, PATCH ${baseUrl}/annotations/<id> with {"status":"dismissed","progress":"Needs manual review","resolution":"<short reason>"}.

Keep the resolution short because it is shown inside the iOS widget toast.`;
}
