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
6. The coding agent receives the annotation through MCP.
7. The agent fixes the issue and marks the annotation resolved.

## When To Use This

Use this flow when you want the fastest feedback loop between the iOS Simulator and an AI coding agent.

Good fit for:

- Iterating on UI polish in the Simulator
- Hands-free agent watch mode
- Multiple annotations in one session
- Agents that support MCP, including Cursor and Claude Code

## Setup

Install the MCP server into your agent with:

```bash
npx add-mcp "npx -y sampler-mcp server"
```

Or start it manually:

```bash
npx -y sampler-mcp server
```

The server exposes:

- A local HTTP endpoint for Sampler to send annotations
- MCP tools for agents to read, acknowledge, resolve, and watch annotations
- Local storage for session history

## MCP Tools

The MCP server exposes tools like:

- `sampler_list_sessions`
- `sampler_get_pending`
- `sampler_get_all_pending`
- `sampler_acknowledge`
- `sampler_resolve`
- `sampler_watch_annotations`

The most important tool is `sampler_watch_annotations`, which lets an agent wait for new Sampler feedback and process it as it arrives.

## Simulator Flow

The iOS Simulator can reach a local server running on the Mac through `localhost`, so Sampler can send annotations to:

```text
http://localhost:4747
```

When the server is reachable, the Sampler widget shows a Send to Agent button. That button POSTs the current annotation payload to the local server.

## Watch Mode Prompt

Once MCP sync is configured, tell your coding agent:

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
