# Use Sampler With MCP Live Sync

This workflow is the direct-to-agent experience for Sampler when you are running your app in the iOS Simulator.

## What This Enables

With MCP live sync, a developer can annotate the app in the iOS Simulator and send those comments directly to their coding agent.

The flow:

1. Start the local Sampler MCP server on the Mac.
2. Run the iOS app in the Simulator.
3. Tap the Sampler widget.
4. Annotate the screen.
5. Tap Send to Agent in the Sampler toolbar.
6. The widget shows one persistent status toast while the annotation is processed.
7. In Cursor projects, `sampler-mcp` auto-dispatches a local `cursor-agent` run.
8. The agent fixes the issue, reports progress, rebuilds/relaunches the Simulator app, and marks the annotation resolved.

## When To Use This

Use this flow when you want the fastest feedback loop between the iOS Simulator and an AI coding agent.

Good fit for:

- Iterating on UI polish in the Simulator
- Hands-free agent watch mode
- Multiple annotations in one session
- Agents that support MCP, including Cursor and Claude Code

## Setup

From your app project root, run:

```bash
npx -y sampler-mcp@latest init
```

This writes the project's `.cursor/mcp.json` and automatically picks a working `npx` or `npm exec` command form. Then reload MCP servers in Cursor (Settings > MCP) or restart Cursor.

If `npx` itself fails before `init` can run, try:

```bash
/opt/homebrew/bin/npx -y sampler-mcp@latest init
npm exec --yes --package=sampler-mcp@latest -- sampler-mcp init
```

Or start the server manually:

```bash
npx -y sampler-mcp@latest server --project .
```

To update later:

```bash
npx -y sampler-mcp@latest update
```

The server exposes:

- A local HTTP endpoint for Sampler to send annotations
- MCP tools for agents to read, acknowledge, resolve, and watch annotations
- Local storage for session history
- Optional auto-dispatch through the Cursor CLI (`cursor-agent`) when new annotations arrive

Run `sampler-mcp doctor` to confirm the local store and `cursor-agent` availability.

Cursor MCP config example:

```json
{
  "mcpServers": {
    "sampler": {
      "command": "npx",
      "args": ["-y", "sampler-mcp@latest", "server", "--project", "."]
    }
  }
}
```

If `npx` fails with `npm ERR! cb.apply is not a function`, your shell may be finding an old Node/npm install. `sampler-mcp init` detects this automatically and writes an `npm exec` or absolute-path form instead. If configuring by hand, use the full path to a modern `npx`, commonly `/opt/homebrew/bin/npx` on Apple Silicon Macs.

## Port Conflicts And Multiple Repos

The Simulator bridge uses `http://localhost:4747`, so only one Sampler MCP server can listen there at a time. If Cursor reports `EADDRINUSE 127.0.0.1:4747`, stop the old Sampler MCP server or remove the Home/global Sampler MCP entry, then reload MCP.

```bash
lsof -nP -iTCP:4747 -sTCP:LISTEN
```

For multiple app repos, use project-local `.cursor/mcp.json` files from `sampler-mcp init`. A Home/global MCP entry can point auto-dispatch at the wrong checkout because `--project` controls where `cursor-agent` runs.

Useful logs:

```bash
tail -f ~/Library/Application\ Support/Cursor/logs/*/mcpprocess.log
tail -f ~/.sampler/agent-logs/*.log
```

## MCP Tools

The MCP server exposes tools like:

- `sampler_list_sessions`
- `sampler_get_pending`
- `sampler_get_all_pending`
- `sampler_acknowledge`
- `sampler_resolve`
- `sampler_watch_annotations`

Cursor users normally do not need to call these manually because auto-dispatch starts a local `cursor-agent` run when new feedback arrives. The most important fallback tool is `sampler_watch_annotations`, which lets an active agent wait for new Sampler feedback and process it as it arrives.

## Simulator Flow

The iOS Simulator can reach a local server running on the Mac through `localhost`, so Sampler can send annotations to:

```text
http://localhost:4747
```

When the server is reachable, the Sampler widget shows a Send to Agent button. That button POSTs the current annotation payload to the local server. After the send succeeds, the widget keeps a single status toast visible and polls the server for status/progress changes until the annotation is resolved, dismissed, or times out.

## Auto-Dispatch

When the server runs inside a Cursor project and `cursor-agent` is available on `PATH`, new annotations automatically launch a local agent in that project with `--trust`. The dispatched agent acknowledges the annotation, updates progress text for the widget, makes the code change, rebuilds/relaunches the Simulator app, and resolves the annotation with a short summary.

If the toast shows repeated `Agent reconnecting... retry N` messages, the Cursor API is reconnecting or temporarily overloaded. Sampler surfaces that separately from app setup errors.

To disable this behavior, run:

```bash
npx -y sampler-mcp@latest server --no-dispatch
```

To point auto-dispatch at a specific app checkout, run:

```bash
npx -y sampler-mcp@latest server --project /path/to/ios-app
```

Preflight checklist:

```bash
cursor-agent --version
cursor-agent login
npx -y sampler-mcp@latest doctor --project .
npx -y sampler-mcp@latest server --project .
```

## Version Labels

The in-app settings sheet shows the Swift/iOS widget package version (`Sampler.version`). `sampler-mcp --version` shows the npm MCP server/tooling version. `sampler-mcp update` reports both.

## Watch Mode Fallback

If your MCP client does not use auto-dispatch, tell your coding agent:

```text
Watch for Sampler annotations. When a new annotation arrives, acknowledge it, inspect the relevant code, make the fix, run the appropriate checks, and mark the annotation resolved with a short summary. Continue until I say stop.
```

## Physical Devices

This flow should start with the iOS Simulator.

Physical-device live sync is possible later, but it needs an extra pairing step because a device cannot reach the Mac through `localhost`. Possible future options include:

- Local network IP entry
- Bonjour discovery
- QR-code pairing
- A temporary local tunnel

Until that exists, physical-device users should use the copy/paste workflow.

## Production Safety

MCP sync is Debug-only and lives inside Sampler's existing `DEBUG && os(iOS)` guards, so Release builds keep the same no-op behavior.
