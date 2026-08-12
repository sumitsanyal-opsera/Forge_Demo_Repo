import { aggregateHealth, healthStatusToHttpCode } from '../HealthAggregator.js';
import { HealthStatus } from '../types.js';
import type { ConnectorHealth } from '../types.js';

const HEALTHY: ConnectorHealth = {
  name: 'sf',
  status: HealthStatus.HEALTHY,
  authStatus: 'authenticated',
  apiReachable: true,
  checkedAt: '2024-01-15T12:00:00.000Z',
};

const DEGRADED: ConnectorHealth = {
  name: 'ops',
  status: HealthStatus.DEGRADED,
  authStatus: 'authenticated',
  apiReachable: true,
  rateLimitRemaining: 10,
  checkedAt: '2024-01-15T12:00:00.000Z',
};

const UNHEALTHY: ConnectorHealth = {
  name: 'sf',
  status: HealthStatus.UNHEALTHY,
  authStatus: 'unauthenticated',
  apiReachable: false,
  checkedAt: '2024-01-15T12:00:00.000Z',
  error: 'Auth failed',
};

describe('aggregateHealth', () => {
  it('returns HEALTHY when all connectors are healthy', () => {
    const result = aggregateHealth([HEALTHY, { ...HEALTHY, name: 'ops' }]);
    expect(result.status).toBe(HealthStatus.HEALTHY);
  });

  it('returns UNHEALTHY if any connector is unhealthy', () => {
    const result = aggregateHealth([HEALTHY, UNHEALTHY]);
    expect(result.status).toBe(HealthStatus.UNHEALTHY);
  });

  it('UNHEALTHY takes priority over DEGRADED', () => {
    const result = aggregateHealth([DEGRADED, UNHEALTHY]);
    expect(result.status).toBe(HealthStatus.UNHEALTHY);
  });

  it('returns DEGRADED if any connector is degraded and none are unhealthy', () => {
    const result = aggregateHealth([HEALTHY, DEGRADED]);
    expect(result.status).toBe(HealthStatus.DEGRADED);
  });

  it('returns UNHEALTHY for empty connector list', () => {
    const result = aggregateHealth([]);
    expect(result.status).toBe(HealthStatus.UNHEALTHY);
    expect(result.connectors).toEqual({});
  });

  it('includes all connectors in the output keyed by name', () => {
    const result = aggregateHealth([HEALTHY, DEGRADED]);
    expect(Object.keys(result.connectors)).toHaveLength(2);
    expect(result.connectors['sf']).toBe(HEALTHY);
    expect(result.connectors['ops']).toBe(DEGRADED);
  });

  it('checkedAt is an ISO timestamp', () => {
    const result = aggregateHealth([HEALTHY]);
    expect(() => new Date(result.checkedAt)).not.toThrow();
    expect(result.checkedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });
});

describe('healthStatusToHttpCode', () => {
  it('maps HEALTHY → 200', () => {
    expect(healthStatusToHttpCode(HealthStatus.HEALTHY)).toBe(200);
  });

  it('maps DEGRADED → 207', () => {
    expect(healthStatusToHttpCode(HealthStatus.DEGRADED)).toBe(207);
  });

  it('maps UNHEALTHY → 503', () => {
    expect(healthStatusToHttpCode(HealthStatus.UNHEALTHY)).toBe(503);
  });
});
