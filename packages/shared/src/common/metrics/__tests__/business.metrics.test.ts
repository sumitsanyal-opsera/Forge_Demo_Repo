import { describe, it, expect, beforeEach } from '@jest/globals';
import { Registry } from 'prom-client';
import { createBusinessMetrics } from '../business.metrics.js';

describe('business metrics', () => {
  let registry: Registry;
  let metrics: ReturnType<typeof createBusinessMetrics>;

  beforeEach(() => {
    registry = new Registry();
    metrics = createBusinessMetrics(registry);
  });

  describe('stuckPipelineDetectionsTotal', () => {
    it('is a counter with correct metric name', async () => {
      const output = await registry.getSingleMetricAsString('stuck_pipeline_detections_total');
      expect(output).toContain('# TYPE stuck_pipeline_detections_total counter');
    });

    it('increments by org, pipeline, and severity labels', async () => {
      metrics.stuckPipelineDetectionsTotal.inc({ org: 'org1', pipeline: 'p1', severity: 'critical' });
      metrics.stuckPipelineDetectionsTotal.inc({ org: 'org1', pipeline: 'p1', severity: 'critical' });
      const output = await registry.getSingleMetricAsString('stuck_pipeline_detections_total');
      expect(output).toContain('org="org1"');
      expect(output).toContain('pipeline="p1"');
      expect(output).toContain('severity="critical"');
      expect(output).toMatch(/stuck_pipeline_detections_total\{.*\} 2/);
    });

    it('tracks separate label combinations independently', async () => {
      metrics.stuckPipelineDetectionsTotal.inc({ org: 'org1', pipeline: 'p1', severity: 'critical' });
      metrics.stuckPipelineDetectionsTotal.inc({ org: 'org2', pipeline: 'p2', severity: 'warning' });
      const output = await registry.getSingleMetricAsString('stuck_pipeline_detections_total');
      expect(output).toContain('org="org1"');
      expect(output).toContain('org="org2"');
    });
  });

  describe('detectionLatencySeconds', () => {
    it('is a histogram with correct buckets', async () => {
      const output = await registry.getSingleMetricAsString('detection_latency_seconds');
      expect(output).toContain('# TYPE detection_latency_seconds histogram');
      // Check a few of the specified buckets: 1, 5, 10, 30, 60, 120, 300
      expect(output).toContain('le="1"');
      expect(output).toContain('le="60"');
      expect(output).toContain('le="300"');
    });

    it('observes latency values', async () => {
      metrics.detectionLatencySeconds.observe({ org: 'org1' }, 45);
      const output = await registry.getSingleMetricAsString('detection_latency_seconds');
      expect(output).toContain('detection_latency_seconds_sum{org="org1"}');
      expect(output).toContain('detection_latency_seconds_count{org="org1"} 1');
    });
  });

  describe('falsePositiveRate1h', () => {
    it('is a gauge with correct metric name', async () => {
      const output = await registry.getSingleMetricAsString('false_positive_rate_1h');
      expect(output).toContain('# TYPE false_positive_rate_1h gauge');
    });

    it('sets value per org', async () => {
      metrics.falsePositiveRate1h.set({ org: 'org1' }, 0.03);
      const output = await registry.getSingleMetricAsString('false_positive_rate_1h');
      expect(output).toContain('false_positive_rate_1h{org="org1"} 0.03');
    });
  });

  describe('activeMonitoredPipelines', () => {
    it('is a gauge', async () => {
      const output = await registry.getSingleMetricAsString('active_monitored_pipelines');
      expect(output).toContain('# TYPE active_monitored_pipelines gauge');
    });

    it('tracks per-org counts', async () => {
      metrics.activeMonitoredPipelines.set({ org: 'org1' }, 42);
      const output = await registry.getSingleMetricAsString('active_monitored_pipelines');
      expect(output).toContain('active_monitored_pipelines{org="org1"} 42');
    });
  });

  describe('alertDeliveryLatencySeconds', () => {
    it('is a histogram with correct buckets', async () => {
      const output = await registry.getSingleMetricAsString('alert_delivery_latency_seconds');
      expect(output).toContain('# TYPE alert_delivery_latency_seconds histogram');
      expect(output).toContain('le="1"');
      expect(output).toContain('le="120"');
    });

    it('observes delivery latency by org and channel', async () => {
      metrics.alertDeliveryLatencySeconds.observe({ org: 'org1', channel: 'email' }, 35);
      const output = await registry.getSingleMetricAsString('alert_delivery_latency_seconds');
      expect(output).toContain('alert_delivery_latency_seconds_count{org="org1",channel="email"} 1');
    });
  });
});
