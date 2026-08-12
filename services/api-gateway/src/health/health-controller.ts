import { Router } from 'express';
import { checkDatabaseHealth } from '@opsera/shared';

/**
 * Health check endpoints excluded from WAF, auth, and rate limiting.
 * /health/live  — liveness probe (is the process running?)
 * /health/ready — readiness probe (is the process ready to serve traffic?)
 */
export function createHealthRouter(): Router {
  const router = Router();

  router.get('/live', (_req, res) => {
    res.status(200).json({ status: 'ok', probe: 'liveness' });
  });

  router.get('/ready', (_req, res) => {
    void (async () => {
      const dbHealth = await checkDatabaseHealth();
      const isReady = dbHealth.healthy;

      res.status(isReady ? 200 : 503).json({
        status: isReady ? 'ok' : 'degraded',
        probe: 'readiness',
        checks: {
          database: dbHealth,
        },
      });
    })();
  });

  return router;
}
