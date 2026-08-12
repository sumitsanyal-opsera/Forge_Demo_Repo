/**
 * Dashboard Service — entry point
 *
 * Responsible for:
 *  - Aggregating execution metrics from Detection and Baseline services
 *  - Serving time-range queries with org-level filtering and pipeline drill-down
 *  - Providing real-time pipeline state (from Redis) and historical trends (from PostgreSQL)
 *  - Powering the Pipeline Health Dashboard React SPA
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

const SERVICE_NAME = 'dashboard-service';
const PORT = process.env['DASHBOARD_SERVICE_PORT'] ?? '3004';

const logger = createLogger(SERVICE_NAME);
const app = express();

// ── Middleware ────────────────────────────────────────────────────────────────

app.use(express.json());
app.use(createHttpMetricsMiddleware());

// ── Health check ──────────────────────────────────────────────────────────────

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE_NAME });
});

// ── Metrics ───────────────────────────────────────────────────────────────────

app.use('/metrics', createMetricsRouter());

// ── Routes (added in subsequent WOs) ─────────────────────────────────────────

// TODO: Mount dashboard metrics and pipeline-state routers here.

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
