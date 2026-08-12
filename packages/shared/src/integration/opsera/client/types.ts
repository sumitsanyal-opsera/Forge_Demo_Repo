/**
 * Domain types for the Opsera API client.
 */

/** Possible states of an Opsera pipeline execution. */
export enum PipelineStatus {
  PENDING = 'pending',
  RUNNING = 'running',
  SUCCESS = 'success',
  FAILED = 'failed',
  CANCELLED = 'cancelled',
  STUCK = 'stuck',
}

/** An individual step within a pipeline configuration. */
export interface PipelineStep {
  id: string;
  name: string;
  type: string;
  order: number;
  /** Step-specific configuration — may contain tool credentials; never log at INFO+. */
  config?: Record<string, unknown>;
}

/**
 * Pipeline configuration payload.
 * May contain sensitive tool credentials in `metadata` — never log the full
 * config object at INFO level or above.
 */
export interface PipelineConfig {
  steps: PipelineStep[];
  timeout?: number;
  retries?: number;
  metadata?: Record<string, unknown>;
}

/** A fully materialised pipeline record returned by the Opsera API. */
export interface Pipeline {
  id: string;
  name: string;
  orgId: string;
  status: PipelineStatus;
  createdAt: string;
  updatedAt: string;
  config: PipelineConfig;
  tags?: string[];
  owner?: string;
}

/** A single execution run of a pipeline. */
export interface PipelineRun {
  runId: string;
  pipelineId: string;
  status: PipelineStatus;
  startedAt?: string;
  completedAt?: string;
  triggeredBy?: string;
  metadata?: Record<string, unknown>;
}

/** Parameters accepted by the pipeline trigger endpoint. */
export interface TriggerPipelineParams {
  branch?: string;
  environment?: string;
  parameters?: Record<string, unknown>;
}

/** Filter options for listing pipelines. Supports both pagination strategies. */
export interface PipelineListFilters {
  status?: PipelineStatus;
  tag?: string;
  owner?: string;
  fromDate?: string;
  toDate?: string;
  /** Offset-based pagination: page number (1-indexed). */
  page?: number;
  /** Number of records per page. Defaults to 20. */
  limit?: number;
  /** Cursor-based pagination: opaque cursor from the previous response. */
  cursor?: string;
}

/**
 * Envelope returned by paginated Opsera list endpoints.
 * Supports both offset-based and cursor-based pagination.
 */
export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page?: number;
  limit?: number;
  /** Cursor pointing to the next page (cursor-based pagination). */
  nextCursor?: string;
  /** Whether additional pages are available. */
  hasMore: boolean;
}

/** An entry in the Opsera tool registry. */
export interface ToolRegistryEntry {
  id: string;
  name: string;
  type: string;
  version: string;
  capabilities: string[];
  metadata?: Record<string, unknown>;
}

/** Shape of a raw Opsera API error response body. */
export interface OpseraErrorBody {
  code?: string;
  message?: string;
  details?: unknown;
}
