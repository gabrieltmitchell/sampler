import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomUUID } from "node:crypto";
import type { AddressInfo } from "node:net";
import type { AutoDispatchStatus, SamplerAnnotationPayload, SamplerAnnotationStatus } from "./types.js";
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
  autoDispatchStatus?: () => AutoDispatchStatus;
  retryDispatch?: () => void;
}

export function startHttpServer(options: HttpServerOptions) {
  const server = createServer(async (request, response) => {
    try {
      await routeRequest(request, response, options);
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
  options: HttpServerOptions
): Promise<void> {
  const { store, hub } = options;
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
      store: store.rootDir,
      autoDispatch: options.autoDispatchStatus?.() ?? {
        enabled: false,
        state: "disabled",
        healthy: true,
        project: null,
        reason: "auto-dispatch disabled",
        lastError: null,
        lastLogPath: null,
        lastLogEmpty: null,
        pid: null,
        command: null,
        updatedAt: new Date().toISOString()
      }
    });
    return;
  }

  if (request.method === "POST" && url.pathname === "/dispatch/retry") {
    if (!options.retryDispatch) {
      writeJson(response, 409, { error: "Auto-dispatch is disabled" });
      return;
    }
    options.retryDispatch();
    writeJson(response, 202, { ok: true, autoDispatch: options.autoDispatchStatus?.() });
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

  const statusMatch = url.pathname.match(/^\/sessions\/([^/]+)\/statuses$/);
  if (request.method === "GET" && statusMatch) {
    writeJson(response, 200, { annotations: store.getSessionStatuses(statusMatch[1]) });
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

  const annotationMatch = url.pathname.match(/^\/annotations\/([^/]+)$/);
  if (request.method === "PATCH" && annotationMatch) {
    const body = (await readJson(request)) as {
      status?: unknown;
      resolution?: unknown;
      progress?: unknown;
    };
    const status = body.status;
    const resolution = typeof body.resolution === "string" ? body.resolution : undefined;
    const hasProgress = Object.hasOwn(body, "progress");
    const progress = typeof body.progress === "string" ? body.progress : null;

    if (status !== undefined && !isAnnotationStatus(status)) {
      writeJson(response, 400, { error: "Invalid annotation status" });
      return;
    }

    if (status === undefined && !hasProgress) {
      writeJson(response, 400, { error: "Expected status or progress" });
      return;
    }

    let annotation = status ? store.updateStatus(annotationMatch[1], status, resolution) : undefined;
    if (hasProgress) {
      annotation = store.updateProgress(annotationMatch[1], progress);
    }

    if (!annotation) {
      writeJson(response, 404, { error: "Annotation not found" });
      return;
    }

    hub.notify();
    writeJson(response, 200, { annotation });
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

function isAnnotationStatus(value: unknown): value is SamplerAnnotationStatus {
  return value === "pending" || value === "acknowledged" || value === "resolved" || value === "dismissed";
}

function writeJson(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(body, null, 2));
}
