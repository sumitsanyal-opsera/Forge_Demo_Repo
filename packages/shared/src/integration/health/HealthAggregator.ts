import { HealthStatus } from './types.js';
import type { AggregateHealth, ConnectorHealth } from './types.js';

/**
 * Combines individual ConnectorHealth results into a single AggregateHealth.
 *
 * Aggregation rules (in priority order):
 *  1. UNHEALTHY if any connector is UNHEALTHY
 *  2. DEGRADED if any connector is DEGRADED (and none are UNHEALTHY)
 *  3. HEALTHY if all connectors are HEALTHY
 *  4. UNHEALTHY if no connectors are provided (nothing to monitor)
 */
export function aggregateHealth(results: ConnectorHealth[]): AggregateHealth {
  const checkedAt = new Date().toISOString();

  if (results.length === 0) {
    return { status: HealthStatus.UNHEALTHY, connectors: {}, checkedAt };
  }

  const connectors: Record<string, ConnectorHealth> = {};
  let status = HealthStatus.HEALTHY;

  for (const result of results) {
    connectors[result.name] = result;

    if (result.status === HealthStatus.UNHEALTHY) {
      status = HealthStatus.UNHEALTHY;
    } else if (result.status === HealthStatus.DEGRADED && status === HealthStatus.HEALTHY) {
      status = HealthStatus.DEGRADED;
    }
  }

  return { status, connectors, checkedAt };
}

/** Maps an AggregateHealth status to its HTTP response code. */
export function healthStatusToHttpCode(status: HealthStatus): number {
  switch (status) {
    case HealthStatus.HEALTHY:
      return 200;
    case HealthStatus.DEGRADED:
      return 207;
    case HealthStatus.UNHEALTHY:
      return 503;
  }
}
