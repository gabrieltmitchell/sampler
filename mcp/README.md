# sampler-mcp

MCP server for Sampler iOS visual feedback annotations.

`sampler-mcp` starts two local interfaces:

- An HTTP server on `http://localhost:4747` that receives annotations from Sampler running in the iOS Simulator.
- An MCP stdio server that exposes annotation tools to coding agents.
- An optional auto-dispatcher that starts `cursor-agent` for new annotations when the Cursor CLI is available.

## Install

Configure an MCP-aware coding agent with:

```bash
npx add-mcp "npx -y sampler-mcp server"
```

Or run the server manually:

```bash
npx -y sampler-mcp server
```

## Commands

```bash
sampler-mcp server          # Start HTTP + MCP server
sampler-mcp doctor          # Check local store and setup
sampler-mcp server --port 8080
sampler-mcp server --project /path/to/ios-app
sampler-mcp server --no-dispatch
sampler-mcp server --mcp-only
```

## MCP Tools

- `sampler_list_sessions`
- `sampler_get_session`
- `sampler_get_pending`
- `sampler_get_all_pending`
- `sampler_acknowledge`
- `sampler_resolve`
- `sampler_dismiss`
- `sampler_watch_annotations`

## HTTP API

- `GET /health`
- `GET /status`
- `GET /sessions`
- `GET /sessions/:id`
- `GET /sessions/:id/statuses`
- `POST /sessions/:id/annotations`
- `PATCH /annotations/:id`
- `GET /sessions/:id/pending`
- `GET /pending`
- `GET /events`

## Storage

By default, annotation data is stored locally at:

```text
~/.sampler/store.db
```

Screenshots are saved under:

```text
~/.sampler/attachments/
```

Use `--store <path>` to change the storage directory.

## Auto-Dispatch

By default, `sampler-mcp server` starts an auto-dispatcher. When a new pending annotation arrives and `cursor-agent` is on `PATH`, the server starts a local Cursor agent in the project directory. The agent acknowledges the annotation, reports progress back to the widget, makes the code change, rebuilds/relaunches the app, and marks the annotation resolved.

Use `--project <path>` to choose the app checkout for dispatched agents. Use `--no-dispatch` to keep the server in manual watch mode.

## Watch Mode Fallback

Tell your agent:

```text
Watch for Sampler annotations. When a new annotation arrives, acknowledge it, inspect the relevant code, make the fix, run the appropriate checks, and mark the annotation resolved with a short summary. Continue until I say stop.
```
