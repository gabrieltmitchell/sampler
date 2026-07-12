import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// Resolve the version from package.json at runtime so the CLI/MCP version can
// never drift from the published package version. Works from both dist/ (built)
// and src/ (tsx dev), since package.json is one level up from either.
export function packageVersion(): string {
  const dir = dirname(fileURLToPath(import.meta.url));
  for (const candidate of [join(dir, "..", "package.json"), join(dir, "package.json")]) {
    try {
      const parsed = JSON.parse(readFileSync(candidate, "utf8")) as { name?: string; version?: string };
      if (parsed.name === "sampler-mcp" && typeof parsed.version === "string") {
        return parsed.version;
      }
    } catch {
      // try next candidate
    }
  }
  return "0.0.0-unknown";
}
