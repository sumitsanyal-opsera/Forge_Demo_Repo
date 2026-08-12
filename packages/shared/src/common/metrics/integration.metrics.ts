import { Counter, Gauge, Histogram, type Registry } from 'prom-client';
import { getSharedRegistry } from './registry.js';

export interface IntegrationMetrics {
  sfApiCallsTotal: Counter<'org' | 'endpoint'>;
  sfApiLatencySeconds: Histogram<'org'>;
  sfCometdConnectionStatus: Gauge<'org'>;
  sfTokenRefreshTotal: Counter<'org' | 'result'>;
  sfApiBudgetUtilization: Gauge<'org'>;
}

export function createIntegrationMetrics(registry: Registry): IntegrationMetrics {
  return {
    sfApiCallsTotal: new Counter({
      name: 'sf_api_calls_total',
      help: 'Total Salesforce REST API calls by org and endpoint',
      labelNames: ['org', 'endpoint'],
      registers: [registry],
    }),

    sfApiLatencySeconds: new Histogram({
      name: 'sf_api_latency_seconds',
      help: 'Salesforce REST API call latency in seconds',
      labelNames: ['org'],
      // Buckets appropriate for Salesforce API with up to 10-min timeout
      buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60, 120, 300, 600],
      registers: [registry],
    }),

    sfCometdConnectionStatus: new Gauge({
      name: 'sf_cometd_connection_status',
      help: 'Salesforce CometD Streaming API connection status (1 = connected, 0 = disconnected)',
      labelNames: ['org'],
      registers: [registry],
    }),

    sfTokenRefreshTotal: new Counter({
      name: 'sf_token_refresh_total',
      help: 'Total Salesforce OAuth token refresh attempts by org and result',
      labelNames: ['org', 'result'],
      registers: [registry],
    }),

    sfApiBudgetUtilization: new Gauge({
      name: 'sf_api_budget_utilization',
      help: 'Salesforce API request budget utilization ratio (0-1)',
      labelNames: ['org'],
      registers: [registry],
    }),
  };
}

let _integrationMetrics: IntegrationMetrics | undefined;

export function getIntegrationMetrics(): IntegrationMetrics {
  if (_integrationMetrics === undefined) {
    _integrationMetrics = createIntegrationMetrics(getSharedRegistry());
  }
  return _integrationMetrics;
}
