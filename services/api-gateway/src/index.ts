/**
 * API Gateway — entry point
 *
 * Responsible for:
 *  - TLS 1.2+ termination (handled by Kubernetes ingress in production)
 *  - Opsera session token validation on every request
 *  - RBAC enforcement (Admin / Release Engineer / Viewer)
 *  - Rate limiting: 100 requests/minute per authenticated user
 *  - Input validation via shared validation middleware
 *  - Routing to downstream services (Baseline, Detection, Alert, Dashboard)
 *  - Security headers: CSP, HSTS, X-Content-Type-Options, X-Frame-Options
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
} from '@opsera/shared';

const SERVICE_NAME = 'api-gateway';
const PORT = process.env['API_GATEWAY_PORT'] ?? '3000';

const logger = createLogger(SERVICE_NAME);
const app = express();

// ── Middleware ────────────────────────────────────────────────────────────────

app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

// Basic security headers (full set added in subsequent WOs via helmet or custom middleware)
app.use((_req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '1; mode=block');
  next();
});

// ── Health check (unauthenticated — for Kubernetes liveness probes) ───────────

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE_NAME });
});

// ── Routes (added in subsequent WOs) ─────────────────────────────────────────

// TODO: Mount /api/v1/* routers (baselines, detection, alerts, dashboard, orgs) here.

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
