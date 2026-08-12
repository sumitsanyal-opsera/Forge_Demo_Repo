import { Router, type RequestHandler } from 'express';
import { type Registry } from 'prom-client';
import { createLogger } from '../../logging/logger.js';
import { getSharedRegistry } from './registry.js';
import { createApiMetrics, getApiMetrics, type ApiMetrics } from './api.metrics.js';
import { normalizePath, isExcludedPath } from './path-normalizer.js';

const logger = createLogger('metrics-router');

/**
 * Creates an Express Router that exposes GET /metrics in Prometheus exposition format.
 * Mount at /metrics: app.use('/metrics', createMetricsRouter())
 */
export function createMetricsRouter(registry: Registry = getSharedRegistry()): Router {
  const router = Router();

  router.get('/', (_req, res) => {
    void (async () => {
      try {
        const output = await registry.metrics();
        res.setHeader('Content-Type', registry.contentType);
        res.status(200).send(output);
      } catch (err) {
        logger.error('Metrics collection failed', err instanceof Error ? err : undefined, {
          correlationId: (_req as Record<string, unknown>)['correlationId'] as string | undefined,
        });
        res.status(503).send('Metrics collection failed');
      }
    })();
  });

  return router;
}

/**
 * Creates Express middleware that automatically instruments all HTTP requests.
 * Records http_request_duration_seconds and http_requests_total for each request,
 * excluding /metrics and /health paths.
 *
 * Mount before routes: app.use(createHttpMetricsMiddleware())
 */
export function createHttpMetricsMiddleware(metrics: ApiMetrics = getApiMetrics()): RequestHandler {
  return (req, res, next) => {
    if (isExcludedPath(req.path)) {
      next();
      return;
    }

    const startHrTime = process.hrtime.bigint();
    metrics.httpActiveConnections.inc();

    res.on('finish', () => {
      metrics.httpActiveConnections.dec();

      const durationNs = process.hrtime.bigint() - startHrTime;
      const durationSeconds = Number(durationNs) / 1e9;

      const method = req.method;
      const path = normalizePath(req.path);
      const status = String(res.statusCode);

      metrics.httpRequestDurationSeconds.observe({ method, path, status }, durationSeconds);
      metrics.httpRequestsTotal.inc({ method, path, status });
    });

    next();
  };
}

/**
 * Convenience factory: returns both the metrics router and HTTP instrumentation middleware
 * pre-wired to the same prom-client Registry.
 */
export function createMetricsBundle(registry: Registry = getSharedRegistry()): {
  metricsRouter: Router;
  httpMetricsMiddleware: RequestHandler;
} {
  const apiMetrics = createApiMetrics(registry);
  return {
    metricsRouter: createMetricsRouter(registry),
    httpMetricsMiddleware: createHttpMetricsMiddleware(apiMetrics),
  };
}
