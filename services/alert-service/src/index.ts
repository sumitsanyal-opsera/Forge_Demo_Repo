/**
 * Alert Service — entry point
 *
 * Responsible for:
 *  - Consuming stuck-pipeline alert events from Redis Streams
 *  - Dispatching email notifications via SMTP (STARTTLS/587)
 *  - Managing alert lifecycle: sent → delivered → acknowledged
 *  - Supporting configurable notification preferences (real-time vs digest)
 *  - Managing email recipient lists per pipeline/org
 *
 * Implementation for these features is added in subsequent work orders.
 * This file bootstraps the Express server (for health/recipient management endpoints)
 * and registers shared middleware.
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

const SERVICE_NAME = 'alert-service';
const PORT = process.env['ALERT_SERVICE_PORT'] ?? '3003';

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

// TODO: Mount alert-recipients and alert-history routers here.

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
