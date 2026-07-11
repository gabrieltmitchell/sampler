import Database from "better-sqlite3";
import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import type {
  SamplerAnnotationPayload,
  SamplerAnnotationStatus,
  StoredAnnotation,
  StoredAnnotationWithSession,
  StoredSession
} from "./types.js";

export class SamplerStore {
  private readonly db: Database.Database;
  readonly rootDir: string;

  constructor(rootDir = join(homedir(), ".sampler")) {
    this.rootDir = rootDir;
    mkdirSync(rootDir, { recursive: true });
    mkdirSync(this.attachmentsDir, { recursive: true });
    this.db = new Database(join(rootDir, "store.db"));
    this.db.pragma("journal_mode = WAL");
    this.migrate();
  }

  get attachmentsDir(): string {
    return join(this.rootDir, "attachments");
  }

  upsertPayload(payload: SamplerAnnotationPayload): {
    session: StoredSession;
    annotations: StoredAnnotation[];
  } {
    const now = new Date().toISOString();
    const sessionId = payload.sessionId || randomUUID();
    const appName = payload.source?.appName ?? null;
    const deviceName = payload.source?.deviceName ?? null;
    const systemVersion = payload.source?.systemVersion ?? null;

    const transaction = this.db.transaction(() => {
      this.db.prepare(
        `insert into sessions (id, app_name, device_name, system_version, created_at, updated_at)
         values (?, ?, ?, ?, ?, ?)
         on conflict(id) do update set
           app_name = excluded.app_name,
           device_name = excluded.device_name,
           system_version = excluded.system_version,
           updated_at = excluded.updated_at`
      ).run(sessionId, appName, deviceName, systemVersion, now, now);

      const screenshotPath = this.writeAttachment(sessionId, "screenshot.png", payload.screenshotPngBase64);
      const annotatedPath = this.writeAttachment(sessionId, "annotated.png", payload.annotatedPngBase64);

      const inserted: StoredAnnotation[] = [];
      for (const annotation of payload.annotations ?? []) {
        const annotationRecord = annotation as { id?: string; number?: number; comment?: string };
        const annotationId = annotationRecord.id || randomUUID();
        const number = typeof annotationRecord.number === "number" ? annotationRecord.number : null;
        const comment = typeof annotationRecord.comment === "string" ? annotationRecord.comment : null;
        const payloadJson = JSON.stringify(
          {
            sessionId,
            source: payload.source,
            capture: payload.capture,
            annotation,
            markdown: payload.markdown,
            createdAt: payload.createdAt ?? now
          },
          null,
          2
        );

        this.db.prepare(
          `insert into annotations (
             id, session_id, number, comment, status, payload_json,
             screenshot_path, annotated_path, created_at, updated_at
           )
           values (?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?)
           on conflict(id) do update set
             number = excluded.number,
             comment = excluded.comment,
             payload_json = excluded.payload_json,
             screenshot_path = excluded.screenshot_path,
             annotated_path = excluded.annotated_path,
             updated_at = excluded.updated_at`
        ).run(annotationId, sessionId, number, comment, payloadJson, screenshotPath, annotatedPath, now, now);

        inserted.push(this.getAnnotation(annotationId)!);
      }

      return {
        session: this.getSession(sessionId)!,
        annotations: inserted
      };
    });

    return transaction();
  }

  listSessions(): StoredSession[] {
    return this.db.prepare(
      `select id,
              app_name as appName,
              device_name as deviceName,
              system_version as systemVersion,
              created_at as createdAt,
              updated_at as updatedAt
       from sessions
       order by updated_at desc`
    ).all() as StoredSession[];
  }

  getSession(id: string): StoredSession | undefined {
    return this.db.prepare(
      `select id,
              app_name as appName,
              device_name as deviceName,
              system_version as systemVersion,
              created_at as createdAt,
              updated_at as updatedAt
       from sessions
       where id = ?`
    ).get(id) as StoredSession | undefined;
  }

  getSessionAnnotations(sessionId: string): StoredAnnotation[] {
    return this.db.prepare(
      `select id,
              session_id as sessionId,
              number,
              comment,
              status,
              payload_json as payloadJson,
              screenshot_path as screenshotPath,
              annotated_path as annotatedPath,
              created_at as createdAt,
              updated_at as updatedAt,
              resolved_at as resolvedAt,
              resolution
       from annotations
       where session_id = ?
       order by created_at asc, number asc`
    ).all(sessionId) as StoredAnnotation[];
  }

  getPending(sessionId?: string): StoredAnnotationWithSession[] {
    const query = `select annotations.id,
                          annotations.session_id as sessionId,
                          annotations.number,
                          annotations.comment,
                          annotations.status,
                          annotations.payload_json as payloadJson,
                          annotations.screenshot_path as screenshotPath,
                          annotations.annotated_path as annotatedPath,
                          annotations.created_at as createdAt,
                          annotations.updated_at as updatedAt,
                          annotations.resolved_at as resolvedAt,
                          annotations.resolution,
                          sessions.app_name as appName,
                          sessions.device_name as deviceName,
                          sessions.system_version as systemVersion
                   from annotations
                   join sessions on sessions.id = annotations.session_id
                   where annotations.status in ('pending', 'acknowledged')
                   ${sessionId ? "and annotations.session_id = ?" : ""}
                   order by annotations.created_at asc, annotations.number asc`;

    return (sessionId
      ? this.db.prepare(query).all(sessionId)
      : this.db.prepare(query).all()) as StoredAnnotationWithSession[];
  }

  updateStatus(id: string, status: SamplerAnnotationStatus, resolution?: string): StoredAnnotation | undefined {
    const now = new Date().toISOString();
    this.db.prepare(
      `update annotations
       set status = ?,
           resolution = coalesce(?, resolution),
           resolved_at = case when ? in ('resolved', 'dismissed') then ? else resolved_at end,
           updated_at = ?
       where id = ?`
    ).run(status, resolution ?? null, status, now, now, id);

    return this.getAnnotation(id);
  }

  private getAnnotation(id: string): StoredAnnotation | undefined {
    return this.db.prepare(
      `select id,
              session_id as sessionId,
              number,
              comment,
              status,
              payload_json as payloadJson,
              screenshot_path as screenshotPath,
              annotated_path as annotatedPath,
              created_at as createdAt,
              updated_at as updatedAt,
              resolved_at as resolvedAt,
              resolution
       from annotations
       where id = ?`
    ).get(id) as StoredAnnotation | undefined;
  }

  private writeAttachment(sessionId: string, filename: string, base64?: string): string | null {
    if (!base64) {
      return null;
    }
    const sessionDir = join(this.attachmentsDir, sessionId);
    mkdirSync(sessionDir, { recursive: true });
    const path = join(sessionDir, filename);
    writeFileSync(path, Buffer.from(base64, "base64"));
    return path;
  }

  private migrate(): void {
    this.db.exec(`
      create table if not exists sessions (
        id text primary key,
        app_name text,
        device_name text,
        system_version text,
        created_at text not null,
        updated_at text not null
      );

      create table if not exists annotations (
        id text primary key,
        session_id text not null references sessions(id) on delete cascade,
        number integer,
        comment text,
        status text not null default 'pending',
        payload_json text not null,
        screenshot_path text,
        annotated_path text,
        created_at text not null,
        updated_at text not null,
        resolved_at text,
        resolution text
      );

      create index if not exists annotations_session_status_idx
        on annotations(session_id, status);
    `);
  }
}
