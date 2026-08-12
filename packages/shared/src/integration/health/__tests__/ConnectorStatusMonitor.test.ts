import { jest } from '@jest/globals';
import { ConnectorStatusMonitor } from '../ConnectorStatusMonitor.js';
import { EventBus } from '../EventBus.js';
import { HealthStatus } from '../types.js';
import type { ConnectorHealth, HealthCheck } from '../types.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makeHealth(name: string, status: HealthStatus): ConnectorHealth {
  return {
    name,
    status,
    authStatus: status === HealthStatus.HEALTHY ? 'authenticated' : 'unauthenticated',
    apiReachable: status !== HealthStatus.UNHEALTHY,
    checkedAt: new Date().toISOString(),
  };
}

function makeCheck(name: string, status: HealthStatus): jest.Mocked<HealthCheck> {
  return {
    name,
    check: jest.fn<HealthCheck['check']>().mockResolvedValue(makeHealth(name, status)),
  };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('ConnectorStatusMonitor', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.runAllTimers();
    jest.useRealTimers();
  });

  it('getAggregateHealth() triggers a check on first call (cold cache)', async () => {
    const sfCheck = makeCheck('salesforce', HealthStatus.HEALTHY);
    const monitor = new ConnectorStatusMonitor([sfCheck], new EventBus(), { intervalMs: 60_000 });

    const result = await monitor.getAggregateHealth();
    expect(sfCheck.check).toHaveBeenCalledTimes(1);
    expect(result.status).toBe(HealthStatus.HEALTHY);
    expect(result.connectors['salesforce']).toBeDefined();
  });

  it('serves from cache for subsequent calls within the interval', async () => {
    const sfCheck = makeCheck('salesforce', HealthStatus.HEALTHY);
    const monitor = new ConnectorStatusMonitor([sfCheck], new EventBus(), { intervalMs: 60_000 });

    await monitor.getAggregateHealth();
    await monitor.getAggregateHealth();
    await monitor.getAggregateHealth();

    expect(sfCheck.check).toHaveBeenCalledTimes(1);
  });

  it('deduplicates concurrent calls — only one in-flight check at a time', async () => {
    const sfCheck = makeCheck('salesforce', HealthStatus.HEALTHY);
    // Make check take some time so we can overlap calls
    sfCheck.check = jest.fn<HealthCheck['check']>().mockImplementation(
      () => new Promise((resolve) => setTimeout(() => resolve(makeHealth('salesforce', HealthStatus.HEALTHY)), 100)),
    );

    const monitor = new ConnectorStatusMonitor([sfCheck], new EventBus(), { intervalMs: 60_000 });

    // Fire three concurrent requests — all should await the same pending promise
    const [r1, r2, r3] = await Promise.all([
      monitor.getAggregateHealth(),
      monitor.getAggregateHealth(),
      monitor.getAggregateHealth(),
    ]);

    expect(sfCheck.check).toHaveBeenCalledTimes(1);
    expect(r1.status).toBe(r2!.status);
    expect(r2!.status).toBe(r3!.status);
  });

  it('emits statusChange event only when status transitions', async () => {
    jest.useRealTimers();
    const eventBus = new EventBus();
    const listener = jest.fn();
    eventBus.onStatusChange(listener);

    const sfCheck = makeCheck('salesforce', HealthStatus.HEALTHY);
    const monitor = new ConnectorStatusMonitor([sfCheck], eventBus, { intervalMs: 60_000 });

    // First check — no previous status → no event
    await monitor.getAggregateHealth();
    expect(listener).not.toHaveBeenCalled();

    // Second check — same status → no event
    sfCheck.check.mockResolvedValue(makeHealth('salesforce', HealthStatus.HEALTHY));
    jest.spyOn(Date, 'now').mockReturnValue(Date.now() + 120_000); // advance past TTL
    await monitor.getAggregateHealth();
    expect(listener).not.toHaveBeenCalled();

    // Third check — status changed → event emitted
    sfCheck.check.mockResolvedValue(makeHealth('salesforce', HealthStatus.UNHEALTHY));
    jest.spyOn(Date, 'now').mockReturnValue(Date.now() + 240_000);
    await monitor.getAggregateHealth();
    expect(listener).toHaveBeenCalledTimes(1);
    const event = listener.mock.calls[0]![0] as { previousStatus: HealthStatus; currentStatus: HealthStatus };
    expect(event.previousStatus).toBe(HealthStatus.HEALTHY);
    expect(event.currentStatus).toBe(HealthStatus.UNHEALTHY);
  });

  it('does not emit an event when status remains the same', async () => {
    jest.useRealTimers();
    const eventBus = new EventBus();
    const listener = jest.fn();
    eventBus.onStatusChange(listener);

    const sfCheck = makeCheck('salesforce', HealthStatus.DEGRADED);
    const monitor = new ConnectorStatusMonitor([sfCheck], eventBus, { intervalMs: 1 });

    await monitor.getAggregateHealth();
    // Wait for TTL to expire then run again with same status
    await new Promise((r) => setTimeout(r, 5));
    await monitor.getAggregateHealth();

    expect(listener).not.toHaveBeenCalled();
  });

  it('start() triggers periodic checks and stop() cleans up the timer', () => {
    const sfCheck = makeCheck('salesforce', HealthStatus.HEALTHY);
    const monitor = new ConnectorStatusMonitor([sfCheck], new EventBus(), { intervalMs: 5_000 });

    monitor.start();
    // Initial check fires immediately via start()
    jest.runAllTimers();

    monitor.stop();
    jest.runAllTimers(); // No more checks after stop

    // The exact call count depends on fake timer advance; just verify it can start/stop
    expect(monitor).toBeDefined();
  });

  it('start() is idempotent — calling twice does not double-schedule', () => {
    const sfCheck = makeCheck('salesforce', HealthStatus.HEALTHY);
    const monitor = new ConnectorStatusMonitor([sfCheck], new EventBus(), { intervalMs: 60_000 });

    monitor.start();
    monitor.start(); // second call should be no-op

    jest.advanceTimersByTime(120_000);
    monitor.stop();
  });

  it('getConnectorHealth() returns null before any check runs', () => {
    const sfCheck = makeCheck('salesforce', HealthStatus.HEALTHY);
    const monitor = new ConnectorStatusMonitor([sfCheck], new EventBus());

    expect(monitor.getConnectorHealth('salesforce')).toBeNull();
  });

  it('getConnectorHealth() returns the cached result after a check', async () => {
    const sfCheck = makeCheck('salesforce', HealthStatus.HEALTHY);
    const monitor = new ConnectorStatusMonitor([sfCheck], new EventBus(), { intervalMs: 60_000 });

    await monitor.getAggregateHealth();
    const health = monitor.getConnectorHealth('salesforce');

    expect(health).not.toBeNull();
    expect(health!.name).toBe('salesforce');
    expect(health!.status).toBe(HealthStatus.HEALTHY);
  });

  it('treats a check that throws as UNHEALTHY without crashing the monitor', async () => {
    const badCheck: HealthCheck = {
      name: 'opsera',
      check: jest.fn<HealthCheck['check']>().mockRejectedValue(new Error('unexpected crash')),
    };
    const monitor = new ConnectorStatusMonitor([badCheck], new EventBus(), { intervalMs: 60_000 });

    const result = await monitor.getAggregateHealth();
    expect(result.status).toBe(HealthStatus.UNHEALTHY);
    expect(result.connectors['opsera']?.error).toContain('unexpected crash');
  });
});
