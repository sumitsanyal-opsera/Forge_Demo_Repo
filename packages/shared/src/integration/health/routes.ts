/**
 * Health check Express Router.
 *
 * Mount at /health to expose:
 *   GET /health            → AggregateHealth (200 healthy / 207 degraded / 503 unhealthy)
 *   GET /health/salesforce → ConnectorHealth for Salesforce
 *   GET /health/opsera     → ConnectorHealth for Opsera
 *
 * All endpoints read from the ConnectorStatusMonitor cache — no new outbound
 * requests are triggered per HTTP request. Multiple concurrent callers share
 * a single cached result for the duration of the check interval.
 *
 * Note: The WO specifies a Fastify plugin, but the existing codebase uses
 * Express throughout (WO-090). This module exports an Express Router factory
 * for consistency, applying the same /health prefix and status code semantics.
 */

import { Router } from 'express';
import type { Request, Response } from 'express';
import { healthStatusToHttpCode } from './HealthAggregator.js';
import { HealthStatus } from './types.js';
import type { ConnectorStatusMonitor } from './ConnectorStatusMonitor.js';

/**
 * Creates and returns an Express Router with /health endpoints.
 *
 * @param monitor  A ConnectorStatusMonitor instance (start() it before mounting).
 */
export function createHealthRouter(monitor: ConnectorStatusMonitor): Router {
  const router = Router();

  // GET / → aggregate health across all connectors
  router.get('/', (_req: Request, res: Response): void => {
    void (async () => {
      try {
        const aggregate = await monitor.getAggregateHealth();
        res.status(healthStatusToHttpCode(aggregate.status)).json(aggregate);
      } catch (err) {
        // The health endpoint must never return 5xx — represent failure as unhealthy
        res.status(503).json({
          status: HealthStatus.UNHEALTHY,
          connectors: {},
          checkedAt: new Date().toISOString(),
          error: 'Health check subsystem error',
        });
      }
    })();
  });

  // GET /salesforce → Salesforce connector health
  router.get('/salesforce', (_req: Request, res: Response): void => {
    void (async () => {
      try {
        const aggregate = await monitor.getAggregateHealth();
        const health = aggregate.connectors['salesforce'];
        if (health === undefined) {
          res.status(503).json({
            error: 'Salesforce connector is not registered in the health monitor',
          });
          return;
        }
        res.status(healthStatusToHttpCode(health.status)).json(health);
      } catch {
        res.status(503).json({
          name: 'salesforce',
          status: HealthStatus.UNHEALTHY,
          authStatus: 'error',
          apiReachable: false,
          checkedAt: new Date().toISOString(),
          error: 'Health check subsystem error',
        });
      }
    })();
  });

  // GET /opsera → Opsera connector health
  router.get('/opsera', (_req: Request, res: Response): void => {
    void (async () => {
      try {
        const aggregate = await monitor.getAggregateHealth();
        const health = aggregate.connectors['opsera'];
        if (health === undefined) {
          res.status(503).json({
            error: 'Opsera connector is not registered in the health monitor',
          });
          return;
        }
        res.status(healthStatusToHttpCode(health.status)).json(health);
      } catch {
        res.status(503).json({
          name: 'opsera',
          status: HealthStatus.UNHEALTHY,
          authStatus: 'error',
          apiReachable: false,
          checkedAt: new Date().toISOString(),
          error: 'Health check subsystem error',
        });
      }
    })();
  });

  return router;
}
