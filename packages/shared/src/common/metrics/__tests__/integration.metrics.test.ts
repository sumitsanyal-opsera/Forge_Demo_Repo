import { describe, it, expect, beforeEach } from '@jest/globals';
import { Registry } from 'prom-client';
import { createIntegrationMetrics } from '../integration.metrics.js';

describe('integration metrics', () => {
  let registry: Registry;
  let metrics: ReturnType<typeof createIntegrationMetrics>;

  beforeEach(() => {
    registry = new Registry();
    metrics = createIntegrationMetrics(registry);
  });

  describe('sfApiCallsTotal', () => {
    it('is a counter', async () => {
      const output = await registry.getSingleMetricAsString('sf_api_calls_total');
      expect(output).toContain('# TYPE sf_api_calls_total counter');
    });

    it('tracks calls by org and endpoint', async () => {
      metrics.sfApiCallsTotal.inc({ org: 'org1', endpoint: '/services/data/v57.0/query' });
      const output = await registry.getSingleMetricAsString('sf_api_calls_total');
      expect(output).toContain('org="org1"');
      expect(output).toContain('endpoint=');
    });
  });

  describe('sfApiLatencySeconds', () => {
    it('is a histogram with Salesforce-appropriate buckets', async () => {
      const output = await registry.getSingleMetricAsString('sf_api_latency_seconds');
      expect(output).toContain('# TYPE sf_api_latency_seconds histogram');
      // 600s bucket for 10-min timeout
      expect(output).toContain('le="600"');
      expect(output).toContain('le="0.1"');
    });

    it('observes latency per org', async () => {
      metrics.sfApiLatencySeconds.observe({ org: 'org1' }, 1.5);
      const output = await registry.getSingleMetricAsString('sf_api_latency_seconds');
      expect(output).toContain('sf_api_latency_seconds_sum{org="org1"}');
    });
  });

  describe('sfCometdConnectionStatus', () => {
    it('is a gauge', async () => {
      const output = await registry.getSingleMetricAsString('sf_cometd_connection_status');
      expect(output).toContain('# TYPE sf_cometd_connection_status gauge');
    });

    it('sets connected (1) and disconnected (0) states per org', async () => {
      metrics.sfCometdConnectionStatus.set({ org: 'org1' }, 1);
      metrics.sfCometdConnectionStatus.set({ org: 'org2' }, 0);
      const output = await registry.getSingleMetricAsString('sf_cometd_connection_status');
      expect(output).toContain('sf_cometd_connection_status{org="org1"} 1');
      expect(output).toContain('sf_cometd_connection_status{org="org2"} 0');
    });
  });

  describe('sfTokenRefreshTotal', () => {
    it('is a counter with org and result labels', async () => {
      const output = await registry.getSingleMetricAsString('sf_token_refresh_total');
      expect(output).toContain('# TYPE sf_token_refresh_total counter');
    });

    it('tracks success and failure refreshes separately', async () => {
      metrics.sfTokenRefreshTotal.inc({ org: 'org1', result: 'success' });
      metrics.sfTokenRefreshTotal.inc({ org: 'org1', result: 'failure' });
      metrics.sfTokenRefreshTotal.inc({ org: 'org1', result: 'success' });
      const output = await registry.getSingleMetricAsString('sf_token_refresh_total');
      expect(output).toMatch(/sf_token_refresh_total\{.*result="success".*\} 2/);
      expect(output).toMatch(/sf_token_refresh_total\{.*result="failure".*\} 1/);
    });
  });

  describe('sfApiBudgetUtilization', () => {
    it('is a gauge', async () => {
      const output = await registry.getSingleMetricAsString('sf_api_budget_utilization');
      expect(output).toContain('# TYPE sf_api_budget_utilization gauge');
    });

    it('sets utilization ratio per org', async () => {
      metrics.sfApiBudgetUtilization.set({ org: 'org1' }, 0.72);
      const output = await registry.getSingleMetricAsString('sf_api_budget_utilization');
      expect(output).toContain('sf_api_budget_utilization{org="org1"} 0.72');
    });
  });
});
