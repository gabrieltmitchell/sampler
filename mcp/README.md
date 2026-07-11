# sampler-mcp

MCP server for Sampler iOS visual feedback annotations.

`sampler-mcp` starts two local interfaces:

- An HTTP server on `http://localhost:4747` that receives annotations from Sampler running in the iOS Simulator.
- An MCP stdio server that exposes annotation tools to coding agents.

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
- `POST /sessions/:id/annotations`
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

## Watch Mode

Tell your agent:

```text
Watch for Sampler annotations. When a new annotation arrives, acknowledge it, inspect the relevant code, make the fix, run the appropriate checks, and mark the annotation resolved with a short summary. Continue until I say stop.
```
