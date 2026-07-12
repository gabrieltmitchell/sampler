import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { AnnotationHub } from "./http.js";
import { SamplerStore } from "./store.js";
import type { StoredAnnotationWithSession } from "./types.js";

export async function startMcpServer(store: SamplerStore, hub: AnnotationHub): Promise<void> {
  const server = new McpServer({
    name: "sampler-mcp",
    version: "0.1.0"
  });

  server.tool("sampler_list_sessions", "List Sampler annotation sessions", {}, async () => {
    return jsonResponse({ sessions: store.listSessions() });
  });

  server.tool(
    "sampler_get_session",
    "Get a Sampler session and all annotations in it",
    {
      sessionId: z.string().describe("Sampler session id")
    },
    async ({ sessionId }) => {
      const session = store.getSession(sessionId);
      if (!session) {
        return jsonResponse({ error: "Session not found", sessionId });
      }
      return jsonResponse({
        session,
        annotations: store.getSessionAnnotations(sessionId)
      });
    }
  );

  server.tool(
    "sampler_get_pending",
    "Get pending or acknowledged annotations for a specific Sampler session",
    {
      sessionId: z.string().describe("Sampler session id")
    },
    async ({ sessionId }) => jsonResponse({ annotations: summarizeAnnotations(store.getPending(sessionId)) })
  );

  server.tool(
    "sampler_get_all_pending",
    "Get pending or acknowledged annotations across all Sampler sessions",
    {},
    async () => jsonResponse({ annotations: summarizeAnnotations(store.getPending()) })
  );

  server.tool(
    "sampler_acknowledge",
    "Mark a Sampler annotation as acknowledged",
    {
      annotationId: z.string().describe("Sampler annotation id")
    },
    async ({ annotationId }) => {
      const annotation = store.updateStatus(annotationId, "acknowledged");
      return jsonResponse({ annotation });
    }
  );

  server.tool(
    "sampler_resolve",
    "Mark a Sampler annotation as resolved",
    {
      annotationId: z.string().describe("Sampler annotation id"),
      summary: z.string().describe("Short summary of the fix")
    },
    async ({ annotationId, summary }) => {
      const annotation = store.updateStatus(annotationId, "resolved", summary);
      return jsonResponse({ annotation });
    }
  );

  server.tool(
    "sampler_dismiss",
    "Dismiss a Sampler annotation with a reason",
    {
      annotationId: z.string().describe("Sampler annotation id"),
      reason: z.string().describe("Reason the annotation will not be acted on")
    },
    async ({ annotationId, reason }) => {
      const annotation = store.updateStatus(annotationId, "dismissed", reason);
      return jsonResponse({ annotation });
    }
  );

  server.tool(
    "sampler_watch_annotations",
    "Wait for new pending Sampler annotations, then return the current pending batch",
    {
      timeoutSeconds: z.number().min(1).max(600).default(120).describe("Maximum seconds to wait")
    },
    async ({ timeoutSeconds }) => {
      const existing = store.getPending();
      if (existing.length > 0) {
        return jsonResponse({ timedOut: false, annotations: summarizeAnnotations(existing) });
      }

      const notified = await hub.waitForAnnotations(timeoutSeconds * 1000);
      return jsonResponse({
        timedOut: !notified,
        annotations: summarizeAnnotations(store.getPending())
      });
    }
  );

  await server.connect(new StdioServerTransport());
}

function summarizeAnnotations(annotations: StoredAnnotationWithSession[]) {
  return annotations.map((annotation) => ({
    id: annotation.id,
    sessionId: annotation.sessionId,
    appName: annotation.appName,
    deviceName: annotation.deviceName,
    systemVersion: annotation.systemVersion,
    number: annotation.number,
    comment: annotation.comment,
    status: annotation.status,
    progress: annotation.progress,
    resolution: annotation.resolution,
    screenshotPath: annotation.screenshotPath,
    annotatedPath: annotation.annotatedPath,
    createdAt: annotation.createdAt,
    updatedAt: annotation.updatedAt,
    payload: JSON.parse(annotation.payloadJson)
  }));
}

function jsonResponse(value: unknown) {
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(value, null, 2)
      }
    ]
  };
}
