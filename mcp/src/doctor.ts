import { spawnSync } from "node:child_process";
import { accessSync, constants, existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { createServer } from "node:net";
import { join } from "node:path";
import { agentLogsDir, checkCursorAgent, ensureAgentLogsWritable } from "./dispatch.js";
import type { SamplerStore } from "./store.js";

export interface DoctorOptions {
  store: SamplerStore;
  dbPath: string;
  project?: string;
  port: number;
}

export async function runDoctor(options: DoctorOptions): Promise<void> {
  const { store, dbPath, project, port } = options;
  const logCheck = ensureAgentLogsWritable(store);
  const npx = commandInfo("npx", ["--version"]);
  const npm = commandInfo("npm", ["--version"]);
  const cursorAgent = checkCursorAgent();
  const portUsed = await isPortInUse(port);
  const latestAuthError = latestAgentLogAuthError(store);

  console.log("Sampler MCP doctor");
  console.log(`store: ${store.rootDir}`);
  console.log(`database: ${existsSync(dbPath) ? "ok" : "missing"}`);
  console.log(`agent logs: ${logCheck.ok ? "ok" : `not writable (${logCheck.reason})`}`);
  console.log(`agent logs path: ${agentLogsDir(store)}`);
  console.log(`sessions: ${store.listSessions().length}`);
  console.log(`pending annotations: ${store.getPending().length}`);
  console.log(`port ${port}: ${portUsed ? "in use" : "available"}`);
  console.log(`npm: ${npm.ok ? `${npm.version} (${npm.path})` : `missing (${npm.error})`}`);
  console.log(`npx: ${npx.ok ? `${npx.version} (${npx.path})` : `missing/broken (${npx.error})`}`);
  console.log(`cursor-agent: ${cursorAgent.ok ? "ok" : `${cursorAgent.state} (${cursorAgent.reason})`}`);
  console.log(`cursor-agent auth: ${latestAuthError ? "required (latest dispatch log reported authentication required)" : "not verified by doctor"}`);

  if (project) {
    console.log(`project: ${project}`);
    reportSwiftPackagePins(project);
  } else {
    console.log("project: not provided (use --project /path/to/app for app-specific checks)");
  }

  console.log("");
  console.log("Recommended setup:");
  console.log('npx add-mcp "npx -y sampler-mcp@latest server --project ."');
  console.log("");
  console.log("Preflight:");
  console.log("cursor-agent --version");
  console.log("cursor-agent login");
  console.log("npx -y sampler-mcp@latest doctor --project .");

  if (!logCheck.ok) {
    console.log("");
    console.log("Fix agent logs:");
    console.log(`mkdir -p "${agentLogsDir(store)}" && chmod u+w "${agentLogsDir(store)}"`);
  }

  if (!cursorAgent.ok && cursorAgent.state === "invalid_cursor_config") {
    console.log("");
    console.log(`Fix Cursor CLI config: ${cursorAgent.reason}.`);
    console.log("Remove unsupported keys from .cursor/cli.json, then run cursor-agent --version again.");
    if (cursorAgent.output) {
      console.log("");
      console.log("cursor-agent output:");
      console.log(cursorAgent.output);
    }
  } else if (!cursorAgent.ok) {
    console.log("");
    console.log(`Fix cursor-agent: ${cursorAgent.reason}. Install the Cursor CLI from Cursor, then run cursor-agent login.`);
  }

  if (latestAuthError) {
    console.log("");
    console.log("Fix cursor-agent auth: run cursor-agent login or set CURSOR_API_KEY.");
  }

  if (!npx.ok && npx.error.includes("cb.apply")) {
    console.log("");
    console.log("Fix npx: point your MCP config at a modern npx, commonly /opt/homebrew/bin/npx on Apple Silicon Macs.");
  }
}

function commandInfo(command: string, args: string[]): { ok: true; path: string; version: string } | { ok: false; error: string } {
  const pathResult = spawnSync("sh", ["-lc", `command -v ${command}`], { encoding: "utf8", timeout: 3000 });
  const path = pathResult.stdout.trim();
  if (!path) {
    return { ok: false, error: pathResult.stderr.trim() || "not found on PATH" };
  }

  const versionResult = spawnSync(command, args, { encoding: "utf8", timeout: 5000 });
  const output = `${versionResult.stdout}${versionResult.stderr}`.trim();
  if (versionResult.status !== 0) {
    return { ok: false, error: output || `exited with ${versionResult.status}` };
  }

  return { ok: true, path, version: output.split("\n")[0] ?? "ok" };
}

function isPortInUse(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const server = createServer();
    server.once("error", () => resolve(true));
    server.once("listening", () => {
      server.close(() => resolve(false));
    });
    server.listen(port, "127.0.0.1");
  });
}

function latestAgentLogAuthError(store: SamplerStore): boolean {
  const logsDir = agentLogsDir(store);
  if (!existsSync(logsDir)) {
    return false;
  }

  const logs = readdirSync(logsDir)
    .filter((name) => name.endsWith(".log"))
    .map((name) => join(logsDir, name))
    .sort((left, right) => statSync(right).mtimeMs - statSync(left).mtimeMs);

  const latest = logs[0];
  if (!latest) {
    return false;
  }

  const contents = readFileSync(latest, "utf8");
  return contents.includes("Authentication required") || contents.includes("agent login");
}

function reportSwiftPackagePins(project: string): void {
  const resolvedFiles = findPackageResolved(project);
  if (resolvedFiles.length === 0) {
    console.log("swift package pins: no Package.resolved found");
    return;
  }

  for (const file of resolvedFiles) {
    try {
      accessSync(file, constants.R_OK);
      const parsed = JSON.parse(readFileSync(file, "utf8")) as {
        pins?: Array<{
          identity?: string;
          location?: string;
          state?: { revision?: string; branch?: string; version?: string };
        }>;
      };
      const samplerPins = (parsed.pins ?? []).filter((pin) =>
        pin.identity === "sampler" || pin.location?.includes("gabrieltmitchell/sampler") === true
      );
      if (samplerPins.length === 0) {
        continue;
      }
      for (const pin of samplerPins) {
        const revision = pin.state?.revision ?? "unknown";
        const branch = pin.state?.branch ?? "none";
        const version = pin.state?.version ?? "none";
        console.log(`sampler Package.resolved: ${file}`);
        console.log(`sampler resolved revision: ${revision}`);
        console.log(`sampler resolved branch: ${branch}`);
        console.log(`sampler resolved version: ${version}`);
        const remoteMain = remoteMainRevision();
        if (remoteMain) {
          console.log(`sampler remote main: ${remoteMain}`);
          console.log(`sampler main pin: ${remoteMain === revision ? "current" : "behind or different"}`);
        } else {
          console.log("sampler remote main: could not check");
        }
      }
    } catch (error) {
      console.log(`swift package pins: could not read ${file} (${error instanceof Error ? error.message : String(error)})`);
    }
  }
}

function findPackageResolved(root: string): string[] {
  const results: string[] = [];
  const ignored = new Set([".git", "node_modules", "DerivedData", ".build"]);
  const visit = (dir: string, depth: number) => {
    if (depth > 5 || results.length >= 10) {
      return;
    }
    let entries: string[];
    try {
      entries = readdirSync(dir);
    } catch {
      return;
    }
    for (const entry of entries) {
      if (ignored.has(entry)) {
        continue;
      }
      const path = join(dir, entry);
      let stats;
      try {
        stats = statSync(path);
      } catch {
        continue;
      }
      if (stats.isFile() && entry === "Package.resolved") {
        results.push(path);
      } else if (stats.isDirectory()) {
        visit(path, depth + 1);
      }
    }
  };
  visit(root, 0);
  return results;
}

function remoteMainRevision(): string | null {
  const result = spawnSync("git", ["ls-remote", "https://github.com/gabrieltmitchell/sampler", "refs/heads/main"], {
    encoding: "utf8",
    timeout: 8000
  });
  if (result.status !== 0) {
    return null;
  }
  return result.stdout.trim().split(/\s+/)[0] ?? null;
}
