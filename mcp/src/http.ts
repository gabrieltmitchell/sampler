import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomUUID } from "node:crypto";
import type { AddressInfo } from "node:net";
import type { SamplerAnnotationPayload } from "./types.js";
import { SamplerStore } from "./store.js";

type AnnotationListener = () => void;

export class AnnotationHub {
  private listeners = new Set<AnnotationListener>();

  subscribe(listener: AnnotationListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  notify(): void {
    for (const listener of this.listeners) {
      listener();
    }
  }

  waitForAnnotations(timeoutMs: number): Promise<boolean> {
    return new Promise((resolve) => {
      const timeout = setTimeout(() => {
        cleanup();
        resolve(false);
      }, timeoutMs);
      const cleanup = this.subscribe(() => {
        clearTimeout(timeout);
        cleanup();
        resolve(true);
      });
    });
  }
}

export interface HttpServerOptions {
  port: number;
  host?: string;
  store: SamplerStore;
  hub: AnnotationHub;
}

export function startHttpServer(options: HttpServerOptions) {
  const server = createServer(async (request, response) => {
    try {
      await routeRequest(request, response, options.store, options.hub);
    } catch (error) {
      writeJson(response, 500, {
        error: error instanceof Error ? error.message : String(error)
      });
    }
  });

  return new Promise<{ close: () => Promise<void>; url: string }>((resolve, reject) => {
    server.once("error", reject);
    server.listen(options.port, options.host ?? "127.0.0.1", () => {
      const address = server.address() as AddressInfo;
      resolve({
        url: `http://${address.address}:${address.port}`,
        close: () =>
          new Promise<void>((closeResolve, closeReject) => {
            server.close((error) => (error ? closeReject(error) : closeResolve()));
          })
      });
    });
  });
}

async function routeRequest(
  request: IncomingMessage,
  response: ServerResponse,
  store: SamplerStore,
  hub: AnnotationHub
): Promise<void> {
  const url = new URL(request.url ?? "/", "http://localhost");
  addCorsHeaders(response);

  if (request.method === "OPTIONS") {
    response.writeHead(204);
    response.end();
    return;
  }

  if (request.method === "GET" && url.pathname === "/health") {
    writeJson(response, 200, { ok: true, service: "sampler-mcp" });
    return;
  }

  if (request.method === "GET" && url.pathname === "/status") {
    writeJson(response, 200, {
      ok: true,
      sessions: store.listSessions().length,
      pending: store.getPending().length,
      store: store.rootDir
    });
    return;
  }

  if (request.method === "POST" && url.pathname === "/sessions") {
    const sessionId = randomUUID();
    const payload: SamplerAnnotationPayload = {
      sessionId,
      source: {},
      capture: {},
      annotations: []
    };
    const result = store.upsertPayload(payload);
    writeJson(response, 201, result.session);
    return;
  }

  if (request.method === "GET" && url.pathname === "/sessions") {
    writeJson(response, 200, { sessions: store.listSessions() });
    return;
  }

  const sessionMatch = url.pathname.match(/^\/sessions\/([^/]+)$/);
  if (request.method === "GET" && sessionMatch) {
    const session = store.getSession(sessionMatch[1]);
    if (!session) {
      writeJson(response, 404, { error: "Session not found" });
      return;
    }
    writeJson(response, 200, {
      session,
      annotations: store.getSessionAnnotations(session.id)
    });
    return;
  }

  const annotationsMatch = url.pathname.match(/^\/sessions\/([^/]+)\/annotations$/);
  if (request.method === "POST" && annotationsMatch) {
    const payload = (await readJson(request)) as SamplerAnnotationPayload;
    payload.sessionId = annotationsMatch[1];
    const result = store.upsertPayload(payload);
    hub.notify();
    writeJson(response, 201, result);
    return;
  }

  const pendingMatch = url.pathname.match(/^\/sessions\/([^/]+)\/pending$/);
  if (request.method === "GET" && pendingMatch) {
    writeJson(response, 200, { annotations: store.getPending(pendingMatch[1]) });
    return;
  }

  if (request.method === "GET" && url.pathname === "/pending") {
    writeJson(response, 200, { annotations: store.getPending() });
    return;
  }

  if (request.method === "GET" && url.pathname === "/events") {
    response.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive"
    });
    response.write(`event: ready\ndata: ${JSON.stringify({ ok: true })}\n\n`);
    const unsubscribe = hub.subscribe(() => {
      response.write(`event: annotations\ndata: ${JSON.stringify({ pending: store.getPending().length })}\n\n`);
    });
    request.on("close", unsubscribe);
    return;
  }

  writeJson(response, 404, { error: "Not found" });
}

async function readJson(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  if (chunks.length === 0) {
    return {};
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function addCorsHeaders(response: ServerResponse): void {
  response.setHeader("Access-Control-Allow-Origin", "*");
  response.setHeader("Access-Control-Allow-Methods", "GET,POST,PATCH,OPTIONS");
  response.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

function writeJson(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(body, null, 2));
}
