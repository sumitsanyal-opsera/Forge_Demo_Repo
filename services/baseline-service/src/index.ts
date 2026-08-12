/**
 * Baseline Service — entry point
 *
 * Responsible for:
 *  - Computing and storing pipeline execution time baselines (P50/P90/P99 via EWMA)
 *  - Managing threshold configurations per pipeline-org-step combination
 *  - Exposing REST endpoints for threshold CRUD and baseline queries
 *
 * Implementation for these features is added in subsequent work orders.
 * This file bootstraps the Express server and registers shared middleware.
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

const SERVICE_NAME = 'baseline-service';
const PORT = process.env['BASELINE_SERVICE_PORT'] ?? '3001';

const logger = createLogger(SERVICE_NAME);
const app = express();

// ── Middleware ────────────────────────────────────────────────────────────────

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
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

// TODO: Import and mount baseline/threshold routers here.

// ── Error handling (must be last) ────────────────────────────────────────────

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
