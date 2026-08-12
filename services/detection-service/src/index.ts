/**
 * Detection Service — entry point
 *
 * Responsible for:
 *  - Consuming deployment state events from Redis Streams
 *  - Running the stuck-pipeline detection state machine
 *    (monitoring → at_risk → potentially_stuck → confirmed_stuck → resolved)
 *  - Evaluating thresholds against baselines via the Baseline Service REST API
 *  - Emitting stuck-pipeline alerts to Redis Streams for the Alert Service
 *
 * Implementation for these features is added in subsequent work orders.
 * This file bootstraps the Express server (for health/metrics endpoints) and
 * registers shared middleware.
 */

import express from 'express';
import {
  createLogger,
  errorMiddleware,
  registerProcessHandlers,
  disconnectDatabase,
  createMetricsRouter,
  createHttpMetricsMiddleware,
} from '@opsera/shared';

const SERVICE_NAME = 'detection-service';
const PORT = process.env['DETECTION_SERVICE_PORT'] ?? '3002';

const logger = createLogger(SERVICE_NAME);
const app = express();

// ── Middleware ────────────────────────────────────────────────────────────────

app.use(express.json());
app.use(createHttpMetricsMiddleware());

// ── Health check ──────────────────────────────────────────────────────────────

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE_NAME });
});

// Kubernetes / docker-compose probe endpoints
app.get('/api/v1/health/live', (_req, res) => {
  res.json({ status: 'ok', probe: 'liveness', service: SERVICE_NAME });
});

app.get('/api/v1/health/ready', (_req, res) => {
  res.json({ status: 'ok', probe: 'readiness', service: SERVICE_NAME });
});

// ── Metrics ───────────────────────────────────────────────────────────────────

app.use('/metrics', createMetricsRouter());

// ── Routes (added in subsequent WOs) ─────────────────────────────────────────

// TODO: Mount detection-status router and Redis Streams consumer here.

// ── Error handling ────────────────────────────────────────────────────────────

app.use(errorMiddleware);

// ── Process handlers ──────────────────────────────────────────────────────────

registerProcessHandlers(async () => {
  await disconnectDatabase();
});

// ── Start server ──────────────────────────────────────────────────────────────

app.listen(Number(PORT), () => {
  logger.info(`${SERVICE_NAME} listening`, { port: PORT });
});

export { app };
