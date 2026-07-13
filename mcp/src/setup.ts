import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { reportSwiftPackagePins } from "./doctor.js";
import { samplerPortStatus } from "./port.js";
import { packageVersion } from "./version.js";

interface Runner {
  command: string;
  args: string[];
  label: string;
}

/**
 * Some machines have a broken npx shim on PATH (classic symptom:
 * "npm ERR! cb.apply is not a function"), so probe candidates and fall back
 * to `npm exec` before writing anything into the Cursor config.
 */
function detectRunner(projectPath: string): Runner | null {
  const serverArgs = ["-y", "sampler-mcp@latest", "server", "--project", projectPath];
  const npxCandidates = ["npx", "/opt/homebrew/bin/npx", "/usr/local/bin/npx"];

  for (const npx of npxCandidates) {
    const result = spawnSync(npx, ["--version"], { encoding: "utf8", timeout: 10_000 });
    if (result.status === 0) {
      return { command: npx, args: serverArgs, label: `${npx} (npx)` };
    }
  }

  const npmResult = spawnSync("npm", ["--version"], { encoding: "utf8", timeout: 10_000 });
  if (npmResult.status === 0) {
    return {
      command: "npm",
      args: ["exec", "--yes", "--package=sampler-mcp@latest", "--", "sampler-mcp", "server", "--project", projectPath],
      label: "npm exec (npx unavailable or broken)"
    };
  }

  return null;
}

export interface InitOptions {
  project: string;
  global?: boolean;
}

export async function runInit(options: InitOptions): Promise<void> {
  const projectPath = resolve(options.project);
  const configPath = options.global
    ? join(homedir(), ".cursor", "mcp.json")
    : join(projectPath, ".cursor", "mcp.json");

  const runner = detectRunner(projectPath);
  if (!runner) {
    console.error("No working npx or npm found. Install Node.js (https://nodejs.org) and retry.");
    console.error("If npx itself is broken, try:");
    console.error("/opt/homebrew/bin/npx -y sampler-mcp@latest init");
    console.error("npm exec --yes --package=sampler-mcp@latest -- sampler-mcp init");
    process.exitCode = 1;
    return;
  }

  const existingSampler = await samplerPortStatus(4747);

  let config: { mcpServers?: Record<string, unknown> } = {};
  if (existsSync(configPath)) {
    try {
      config = JSON.parse(readFileSync(configPath, "utf8")) as { mcpServers?: Record<string, unknown> };
    } catch (error) {
      console.error(`Could not parse existing ${configPath}: ${error instanceof Error ? error.message : String(error)}`);
      console.error("Fix or remove that file, then run init again.");
      process.exitCode = 1;
      return;
    }
  }

  config.mcpServers = {
    ...config.mcpServers,
    sampler: { command: runner.command, args: runner.args }
  };

  mkdirSync(dirname(configPath), { recursive: true });
  writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);

  console.log("Sampler MCP configured.");
  console.log(`config: ${configPath}`);
  console.log(`runner: ${runner.label}`);
  console.log(`project: ${projectPath}`);
  if (options.global) {
    console.log("");
    console.log("Warning: --global writes a Home MCP entry. For multiple app repos, project-local .cursor/mcp.json is safer because Sampler auto-dispatch uses the configured --project path.");
  }
  if (existingSampler.ok) {
    console.log("");
    console.log(`Note: another Sampler MCP server is already running on port 4747 (${existingSampler.version ?? "unknown version"}).`);
    console.log("After changing config, stop/reload the old MCP server in Cursor so this project owns the Simulator bridge.");
  }
  console.log("");
  console.log("Next steps:");
  console.log("1. In Cursor, reload MCP servers (Settings > MCP) or restart Cursor.");
  console.log("2. Sign in the Cursor CLI if needed: cursor-agent login");
  console.log("3. Verify: npx -y sampler-mcp@latest doctor --project .");
  console.log("4. Build and run your app in the iOS Simulator, then send an annotation from the Sampler widget.");
}

export interface UpdateOptions {
  project: string;
}

export function runUpdate(options: UpdateOptions): void {
  const projectPath = resolve(options.project);
  const current = packageVersion();
  const latest = npmLatestVersion();

  console.log("Sampler MCP update check");
  console.log(`running version: ${current}`);
  console.log(`npm latest: ${latest ?? "could not reach npm registry"}`);

  if (latest && latest !== current) {
    console.log("");
    console.log("A newer sampler-mcp is available.");
    console.log("Cursor configs written by init use sampler-mcp@latest, so just restart the MCP:");
    console.log("in Cursor, toggle the sampler MCP server off/on (Settings > MCP) or restart Cursor.");
  } else if (latest) {
    console.log("sampler-mcp server: up to date.");
  }

  console.log("");
  console.log("Swift package (widget) status:");
  const latestTag = latestRemoteTag();
  if (latestTag) {
    console.log(`latest release tag: ${latestTag}`);
  }
  reportSwiftPackagePins(projectPath);
  console.log("");
  console.log("To update the widget in your app:");
  console.log("Xcode: File > Packages > Update to Latest Package Versions");
  console.log("or CLI: xcodebuild -resolvePackageDependencies");
}

function npmLatestVersion(): string | null {
  const result = spawnSync("npm", ["view", "sampler-mcp", "version"], { encoding: "utf8", timeout: 15_000 });
  if (result.status !== 0) {
    return null;
  }
  return result.stdout.trim() || null;
}

function latestRemoteTag(): string | null {
  const result = spawnSync("git", ["ls-remote", "--tags", "https://github.com/gabrieltmitchell/sampler"], {
    encoding: "utf8",
    timeout: 10_000
  });
  if (result.status !== 0) {
    return null;
  }

  const versions = result.stdout
    .split("\n")
    .map((line) => line.match(/refs\/tags\/v?(\d+\.\d+\.\d+)$/)?.[1])
    .filter((tag): tag is string => Boolean(tag))
    .sort((left, right) => {
      const l = left.split(".").map(Number);
      const r = right.split(".").map(Number);
      return (l[0] - r[0]) || (l[1] - r[1]) || (l[2] - r[2]);
    });

  return versions.at(-1) ?? null;
}
