export type SamplerAnnotationStatus = "pending" | "acknowledged" | "resolved" | "dismissed";

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
