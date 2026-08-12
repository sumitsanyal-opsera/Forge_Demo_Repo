import { describe, it, expect, beforeEach } from '@jest/globals';
import { Registry } from 'prom-client';
import { createApiMetrics } from '../api.metrics.js';

describe('api metrics', () => {
  let registry: Registry;
  let metrics: ReturnType<typeof createApiMetrics>;

  beforeEach(() => {
    registry = new Registry();
    metrics = createApiMetrics(registry);
  });

  describe('httpRequestDurationSeconds', () => {
    it('is a histogram with correct metric name', async () => {
      const output = await registry.getSingleMetricAsString('http_request_duration_seconds');
      expect(output).toContain('# TYPE http_request_duration_seconds histogram');
    });

    it('has fine-grained latency buckets covering 5ms to 10s', async () => {
      const output = await registry.getSingleMetricAsString('http_request_duration_seconds');
      expect(output).toContain('le="0.005"');
      expect(output).toContain('le="0.5"');
      expect(output).toContain('le="10"');
    });

    it('observes duration with method, path, status labels', async () => {
      metrics.httpRequestDurationSeconds.observe({ method: 'GET', path: '/api/v1/pipelines', status: '200' }, 0.043);
      const output = await registry.getSingleMetricAsString('http_request_duration_seconds');
      expect(output).toContain('method="GET"');
      expect(output).toContain('path="/api/v1/pipelines"');
      expect(output).toContain('status="200"');
      expect(output).toContain('http_request_duration_seconds_count{method="GET",path="/api/v1/pipelines",status="200"} 1');
    });
  });

  describe('httpRequestsTotal', () => {
    it('is a counter with correct metric name', async () => {
      const output = await registry.getSingleMetricAsString('http_requests_total');
      expect(output).toContain('# TYPE http_requests_total counter');
    });

    it('increments with method, path, status labels', async () => {
      metrics.httpRequestsTotal.inc({ method: 'POST', path: '/api/v1/alerts', status: '201' });
      metrics.httpRequestsTotal.inc({ method: 'POST', path: '/api/v1/alerts', status: '201' });
      const output = await registry.getSingleMetricAsString('http_requests_total');
      expect(output).toMatch(/http_requests_total\{method="POST",path="\/api\/v1\/alerts",status="201"\} 2/);
    });
  });

  describe('httpActiveConnections', () => {
    it('is a gauge with correct metric name', async () => {
      const output = await registry.getSingleMetricAsString('http_active_connections');
      expect(output).toContain('# TYPE http_active_connections gauge');
    });

    it('increments and decrements correctly', async () => {
      metrics.httpActiveConnections.inc();
      metrics.httpActiveConnections.inc();
      metrics.httpActiveConnections.dec();
      const output = await registry.getSingleMetricAsString('http_active_connections');
      expect(output).toContain('http_active_connections 1');
    });
  });
});
