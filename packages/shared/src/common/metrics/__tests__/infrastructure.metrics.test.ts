import { describe, it, expect, beforeEach } from '@jest/globals';
import { Registry } from 'prom-client';
import { createInfrastructureMetrics } from '../infrastructure.metrics.js';

describe('infrastructure metrics', () => {
  let registry: Registry;
  let metrics: ReturnType<typeof createInfrastructureMetrics>;

  beforeEach(() => {
    registry = new Registry();
    metrics = createInfrastructureMetrics(registry);
  });

  describe('pgConnectionsActive', () => {
    it('is a gauge', async () => {
      const output = await registry.getSingleMetricAsString('pg_connections_active');
      expect(output).toContain('# TYPE pg_connections_active gauge');
    });

    it('defaults to 0 (no NaN on cold start)', async () => {
      const output = await registry.getSingleMetricAsString('pg_connections_active');
      // Gauge without labels — either the line is absent (no observations) or shows 0
      expect(output).not.toContain('NaN');
    });

    it('sets active connection count', async () => {
      metrics.pgConnectionsActive.set(5);
      const output = await registry.getSingleMetricAsString('pg_connections_active');
      expect(output).toContain('pg_connections_active 5');
    });
  });

  describe('pgQueryDurationSeconds', () => {
    it('is a histogram with operation label', async () => {
      const output = await registry.getSingleMetricAsString('pg_query_duration_seconds');
      expect(output).toContain('# TYPE pg_query_duration_seconds histogram');
    });

    it('observes query duration per operation type', async () => {
      metrics.pgQueryDurationSeconds.observe({ operation: 'SELECT' }, 0.015);
      const output = await registry.getSingleMetricAsString('pg_query_duration_seconds');
      expect(output).toContain('operation="SELECT"');
      expect(output).toContain('pg_query_duration_seconds_count{operation="SELECT"} 1');
    });
  });

  describe('redisMemoryUsedBytes', () => {
    it('is a gauge', async () => {
      const output = await registry.getSingleMetricAsString('redis_memory_used_bytes');
      expect(output).toContain('# TYPE redis_memory_used_bytes gauge');
    });

    it('sets memory usage in bytes', async () => {
      metrics.redisMemoryUsedBytes.set(52428800); // 50 MB
      const output = await registry.getSingleMetricAsString('redis_memory_used_bytes');
      expect(output).toContain('redis_memory_used_bytes 52428800');
    });
  });

  describe('redisStreamsConsumerLag', () => {
    it('is a gauge with stream label', async () => {
      const output = await registry.getSingleMetricAsString('redis_streams_consumer_lag');
      expect(output).toContain('# TYPE redis_streams_consumer_lag gauge');
    });

    it('sets lag per stream', async () => {
      metrics.redisStreamsConsumerLag.set({ stream: 'pipeline-events' }, 12);
      const output = await registry.getSingleMetricAsString('redis_streams_consumer_lag');
      expect(output).toContain('redis_streams_consumer_lag{stream="pipeline-events"} 12');
    });
  });

  describe('redisStreamsMessagesProcessedTotal', () => {
    it('is a counter with stream label', async () => {
      const output = await registry.getSingleMetricAsString('redis_streams_messages_processed_total');
      expect(output).toContain('# TYPE redis_streams_messages_processed_total counter');
    });

    it('increments per stream', async () => {
      metrics.redisStreamsMessagesProcessedTotal.inc({ stream: 'pipeline-events' });
      metrics.redisStreamsMessagesProcessedTotal.inc({ stream: 'pipeline-events' });
      const output = await registry.getSingleMetricAsString('redis_streams_messages_processed_total');
      expect(output).toMatch(/redis_streams_messages_processed_total\{stream="pipeline-events"\} 2/);
    });
  });
});
