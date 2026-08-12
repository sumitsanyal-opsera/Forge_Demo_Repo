/**
 * Types for the connector health monitoring subsystem.
 */

/** Overall operational status of a connector or the aggregate system. */
export enum HealthStatus {
  /** All checks pass — auth valid, API reachable, rate limit headroom sufficient. */
  HEALTHY = 'healthy',
  /** Auth OK and API reachable, but rate limit remaining is below 20%. */
  DEGRADED = 'degraded',
  /** Auth failed, API unreachable, or a critical check threw an unhandled error. */
  UNHEALTHY = 'unhealthy',
}

/** Health result for a single connector (Salesforce or Opsera). */
export interface ConnectorHealth {
  /** Connector identifier, e.g. 'salesforce' or 'opsera'. */
  name: string;
  status: HealthStatus;
  /** Authentication state determined during this check. */
  authStatus: 'authenticated' | 'unauthenticated' | 'error';
  /** Whether the connector's API endpoint responded within the timeout. */
  apiReachable: boolean;
  /** Percentage (0–100) of API rate limit remaining at check time. Undefined if unknown. */
  rateLimitRemaining?: number;
  /** ISO timestamp of the last successful health check (authenticated + reachable). */
  lastSuccessAt?: string;
  /** ISO timestamp when this check was performed. */
  checkedAt: string;
  /** Human-readable error if status is not HEALTHY. */
  error?: string;
  /** Round-trip latency for the ping request in milliseconds. */
  latencyMs?: number;
}

/** Combined health view across all registered connectors. */
export interface AggregateHealth {
  /**
   * Rolled-up status:
   *  - HEALTHY if every connector is healthy
   *  - UNHEALTHY if any connector is unhealthy
   *  - DEGRADED otherwise
   */
  status: HealthStatus;
  /** Per-connector health keyed by connector name. */
  connectors: Record<string, ConnectorHealth>;
  /** ISO timestamp when this aggregate was last computed. */
  checkedAt: string;
}

/** Interface that every connector health check must implement. */
export interface HealthCheck {
  readonly name: string;
  check(): Promise<ConnectorHealth>;
}

/** Event emitted by ConnectorStatusMonitor when a connector's status changes. */
export interface StatusChangeEvent {
  connectorName: string;
  previousStatus: HealthStatus;
  currentStatus: HealthStatus;
  health: ConnectorHealth;
  timestamp: string;
}
