import { createLogger } from '../../logging/logger.js';
import { aggregateHealth } from './HealthAggregator.js';
import { HealthStatus } from './types.js';
import type { AggregateHealth, ConnectorHealth, HealthCheck, StatusChangeEvent } from './types.js';
import type { EventBus } from './EventBus.js';

const logger = createLogger('ConnectorStatusMonitor');

export interface ConnectorStatusMonitorConfig {
  /** How often to run the full health check suite. Default: 60 000 ms. */
  intervalMs?: number;
}

/**
 * Runs periodic health checks across all registered connectors, caches the
 * results for the check interval, and emits StatusChangeEvents via EventBus
 * whenever a connector's status transitions (healthy ↔ degraded ↔ unhealthy).
 *
 * Cache semantics: results are valid for one full intervalMs window.
 * Concurrent callers within that window share the same cached aggregate —
 * only one outbound HTTP fan-out happens per interval.
 */
export class ConnectorStatusMonitor {
  private readonly checks: HealthCheck[];
  private readonly eventBus: EventBus;
  private readonly intervalMs: number;

  private intervalHandle: ReturnType<typeof setInterval> | null = null;
  private _cachedAggregate: AggregateHealth | null = null;
  private _cacheTimestamp = 0;
  private _pendingCheck: Promise<AggregateHealth> | null = null;
  private _previousStatuses = new Map<string, HealthStatus>();

  constructor(checks: HealthCheck[], eventBus: EventBus, config?: ConnectorStatusMonitorConfig) {
    this.checks = checks;
    this.eventBus = eventBus;
    this.intervalMs = config?.intervalMs ?? 60_000;
  }

  /**
   * Starts the background check loop and runs an initial check immediately.
   * Calling start() on an already-running monitor is a no-op.
   */
  start(): void {
    if (this.intervalHandle !== null) return;
    void this.runChecks();
    this.intervalHandle = setInterval(() => { void this.runChecks(); }, this.intervalMs);
    logger.info('ConnectorStatusMonitor started', {
      connectorCount: this.checks.length,
      intervalMs: this.intervalMs,
    });
  }

  /**
   * Stops the background check loop and cleans up the timer.
   * Safe to call even if the monitor was never started.
   */
  stop(): void {
    if (this.intervalHandle !== null) {
      clearInterval(this.intervalHandle);
      this.intervalHandle = null;
      logger.info('ConnectorStatusMonitor stopped');
    }
  }

  /**
   * Returns the current aggregate health. Serves from cache if the result
   * is younger than intervalMs. If the cache is stale and a check is already
   * running, callers await the same in-flight Promise (deduplication).
   */
  async getAggregateHealth(): Promise<AggregateHealth> {
    const ageMs = Date.now() - this._cacheTimestamp;
    if (this._cachedAggregate !== null && ageMs < this.intervalMs) {
      return this._cachedAggregate;
    }

    if (this._pendingCheck !== null) {
      return this._pendingCheck;
    }

    this._pendingCheck = this.runChecks().finally(() => {
      this._pendingCheck = null;
    });
    return this._pendingCheck;
  }

  /**
   * Returns the cached health for a specific connector, or null if not yet checked.
   */
  getConnectorHealth(name: string): ConnectorHealth | null {
    return this._cachedAggregate?.connectors[name] ?? null;
  }

  // ── Internal ─────────────────────────────────────────────────────────────────

  private async runChecks(): Promise<AggregateHealth> {
    logger.debug('Running connector health checks', { connectorCount: this.checks.length });

    const settled = await Promise.allSettled(
      this.checks.map((check) => check.check()),
    );

    const now = new Date().toISOString();
    const results: ConnectorHealth[] = [];

    for (let i = 0; i < settled.length; i++) {
      const outcome = settled[i]!;
      const check = this.checks[i]!;

      let health: ConnectorHealth;
      if (outcome.status === 'fulfilled') {
        health = outcome.value;
      } else {
        logger.error('Connector health check threw unexpectedly', outcome.reason, {
          connector: check.name,
        });
        health = {
          name: check.name,
          status: HealthStatus.UNHEALTHY,
          authStatus: 'error',
          apiReachable: false,
          checkedAt: now,
          error: String(outcome.reason),
        };
      }

      results.push(health);
      this.emitTransitionEventIfChanged(check.name, health, now);
    }

    const aggregate = aggregateHealth(results);
    this._cachedAggregate = aggregate;
    this._cacheTimestamp = Date.now();

    logger.debug('Health check cycle complete', { status: aggregate.status });
    return aggregate;
  }

  private emitTransitionEventIfChanged(
    connectorName: string,
    health: ConnectorHealth,
    timestamp: string,
  ): void {
    const previousStatus = this._previousStatuses.get(connectorName);
    this._previousStatuses.set(connectorName, health.status);

    if (previousStatus !== undefined && previousStatus !== health.status) {
      const event: StatusChangeEvent = {
        connectorName,
        previousStatus,
        currentStatus: health.status,
        health,
        timestamp,
      };
      logger.info('Connector status changed', {
        connector: connectorName,
        from: previousStatus,
        to: health.status,
      });
      this.eventBus.emitStatusChange(event);
    }
  }
}
