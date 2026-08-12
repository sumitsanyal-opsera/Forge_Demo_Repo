/**
 * API Gateway — entry point
 *
 * Middleware stack (executed in order):
 *  1. CORS preflight (before auth — must handle OPTIONS before session checks)
 *  2. WAF (OWASP CRS pattern matching)
 *  3. Body size limit (reject oversized payloads before parsing)
 *  4. JSON body parser (with size limit as defence-in-depth)
 *  5. XML rejection (XXE prevention)
 *  6. Security headers (injected on every response)
 *  7. Health endpoints (excluded from auth, WAF, and rate limiting)
 *  8. Metrics endpoint (excluded from auth and rate limiting)
 *  9. HTTP metrics instrumentation
 * 10. Brute-force check (reject locked-out users before rate limiter)
 * 11. Rate limiter (100 req/min per authenticated user)
 * 12. Routes (added in subsequent WOs)
 * 13. Error handler (last middleware)
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
import { createSecurityHeadersMiddleware } from './middleware/security-headers.js';
import { createCorsMiddleware } from './middleware/cors.js';
import { createBodySizeLimitMiddleware } from './middleware/body-size-limit.js';
import { createXmlRejectionMiddleware } from './middleware/xml-rejection.js';
import { createWafMiddleware } from './middleware/waf.js';
import { createHealthRouter } from './health/health-controller.js';
import { loadGatewayConfig } from './config/gateway.config.js';

const SERVICE_NAME = 'api-gateway';
const PORT = process.env['API_GATEWAY_PORT'] ?? '3000';

const logger = createLogger(SERVICE_NAME);
const config = loadGatewayConfig();
const app = express();

// ── 1. CORS preflight (before auth — handles OPTIONS before session checks) ───

app.use(createCorsMiddleware(config.corsAllowedOrigin));

// ── 2. WAF ────────────────────────────────────────────────────────────────────

app.use(createWafMiddleware({ enabled: config.wafEnabled }));

// ── 3 & 4. Body size limit + JSON body parser ─────────────────────────────────

app.use(createBodySizeLimitMiddleware(config.bodySizeLimitBytes));
app.use(express.json({ limit: config.bodySizeLimitBytes }));
app.use(express.urlencoded({ extended: true, limit: config.bodySizeLimitBytes }));

// ── 5. XML rejection (XXE prevention) ─────────────────────────────────────────

app.use(createXmlRejectionMiddleware());

// ── 6. Security headers (applied to every response) ───────────────────────────

app.use(createSecurityHeadersMiddleware());

// ── 7. Health endpoints (excluded from auth, WAF, and rate limiting) ──────────

app.use('/health', createHealthRouter());

// ── 8 & 9. Metrics endpoint + HTTP instrumentation ───────────────────────────

app.use('/metrics', createMetricsRouter());
app.use(createHttpMetricsMiddleware());

// ── Routes (added in subsequent WOs) ─────────────────────────────────────────

// TODO: Wire brute-force protection and rate limiter once session auth is in place.
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
