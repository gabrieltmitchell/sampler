export type SamplerAnnotationStatus = "pending" | "acknowledged" | "resolved" | "dismissed";

export type AutoDispatchState =
  | "ready"
  | "disabled"
  | "missing_cursor_agent"
  | "invalid_cursor_config"
  | "auth_required"
  | "logs_not_writable"
  | "queued"
  | "agent_starting"
  | "agent_started"
  | "agent_stalled"
  | "agent_reconnecting"
  | "agent_network_error"
  | "running"
  | "agent_completed"
  | "last_run_failed";

export interface SamplerAnnotationPayload {
  sessionId?: string;
  source?: {
    appName?: string;
    deviceName?: string;
    systemVersion?: string;
  };
  capture: unknown;
  annotations: unknown[];
  markdown?: string;
  screenshotPngBase64?: string;
  annotatedPngBase64?: string;
  createdAt?: string;
}

export interface StoredSession {
  id: string;
  appName: string | null;
  deviceName: string | null;
  systemVersion: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface StoredAnnotation {
  id: string;
  sessionId: string;
  number: number | null;
  comment: string | null;
  status: SamplerAnnotationStatus;
  progress: string | null;
  payloadJson: string;
  screenshotPath: string | null;
  annotatedPath: string | null;
  createdAt: string;
  updatedAt: string;
  resolvedAt: string | null;
  resolution: string | null;
}

export interface StoredAnnotationWithSession extends StoredAnnotation {
  appName: string | null;
  deviceName: string | null;
  systemVersion: string | null;
}

export interface StoredAnnotationStatus {
  id: string;
  sessionId: string;
  number: number | null;
  comment: string | null;
  status: SamplerAnnotationStatus;
  progress: string | null;
  resolution: string | null;
  updatedAt: string;
  resolvedAt: string | null;
}

export interface AutoDispatchStatus {
  enabled: boolean;
  state: AutoDispatchState;
  healthy: boolean;
  project: string | null;
  reason: string | null;
  lastError: string | null;
  lastLogPath: string | null;
  lastLogEmpty: boolean | null;
  lastOutput: string | null;
  retryCount: number | null;
  pid: number | null;
  command: string | null;
  activeAnnotationIds: string[];
  updatedAt: string;
}
