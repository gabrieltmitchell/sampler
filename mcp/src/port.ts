export interface PortInUseError extends Error {
  code: "EADDRINUSE";
}

export interface SamplerPortStatus {
  ok: boolean;
  service?: string;
  version?: string;
  store?: string;
  error?: string;
}

export function isPortInUseError(error: unknown): error is PortInUseError {
  return error instanceof Error && "code" in error && error.code === "EADDRINUSE";
}

export function portConflictMessage(port: number, host = "127.0.0.1"): string {
  return [
    `Sampler MCP port ${port} is already in use on ${host}.`,
    "Another Sampler MCP server is probably already running.",
    "Stop the old server, remove the Home/global Sampler MCP entry, or run this project on a different port.",
    `Find the process with: lsof -nP -iTCP:${port} -sTCP:LISTEN`
  ].join(" ");
}

export async function samplerPortStatus(port: number, host = "127.0.0.1"): Promise<SamplerPortStatus> {
  const baseUrl = `http://${host}:${port}`;
  try {
    const [health, status] = await Promise.all([
      fetch(`${baseUrl}/health`).then((response) => response.ok ? response.json() as Promise<Record<string, unknown>> : null),
      fetch(`${baseUrl}/status`).then((response) => response.ok ? response.json() as Promise<Record<string, unknown>> : null)
    ]);

    if (health?.service === "sampler-mcp") {
      return {
        ok: true,
        service: "sampler-mcp",
        version: typeof health.version === "string" ? health.version : undefined,
        store: typeof status?.store === "string" ? status.store : undefined
      };
    }

    return { ok: false, error: `${baseUrl} responded but did not look like sampler-mcp` };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) };
  }
}
