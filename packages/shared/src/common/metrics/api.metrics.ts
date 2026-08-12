import { Counter, Gauge, Histogram, type Registry } from 'prom-client';
import { getSharedRegistry } from './registry.js';

export interface ApiMetrics {
  httpRequestDurationSeconds: Histogram<'method' | 'path' | 'status'>;
  httpRequestsTotal: Counter<'method' | 'path' | 'status'>;
  httpActiveConnections: Gauge;
}

export function createApiMetrics(registry: Registry): ApiMetrics {
  return {
    httpRequestDurationSeconds: new Histogram({
      name: 'http_request_duration_seconds',
      help: 'HTTP request duration in seconds',
      labelNames: ['method', 'path', 'status'],
      buckets: [0.005, 0.01, 0.05, 0.1, 0.5, 1, 2, 5, 10],
      registers: [registry],
    }),

    httpRequestsTotal: new Counter({
      name: 'http_requests_total',
      help: 'Total number of HTTP requests processed',
      labelNames: ['method', 'path', 'status'],
      registers: [registry],
    }),

    httpActiveConnections: new Gauge({
      name: 'http_active_connections',
      help: 'Number of currently active HTTP connections being processed',
      registers: [registry],
    }),
  };
}

let _apiMetrics: ApiMetrics | undefined;

export function getApiMetrics(): ApiMetrics {
  if (_apiMetrics === undefined) {
    _apiMetrics = createApiMetrics(getSharedRegistry());
  }
  return _apiMetrics;
}
