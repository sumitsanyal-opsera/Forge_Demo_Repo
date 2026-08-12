import { Counter, Gauge, Histogram, type Registry } from 'prom-client';
import { getSharedRegistry } from './registry.js';

export interface BusinessMetrics {
  stuckPipelineDetectionsTotal: Counter<'org' | 'pipeline' | 'severity'>;
  detectionLatencySeconds: Histogram<'org'>;
  falsePositiveRate1h: Gauge<'org'>;
  activeMonitoredPipelines: Gauge<'org'>;
  alertDeliveryLatencySeconds: Histogram<'org' | 'channel'>;
}

export function createBusinessMetrics(registry: Registry): BusinessMetrics {
  return {
    stuckPipelineDetectionsTotal: new Counter({
      name: 'stuck_pipeline_detections_total',
      help: 'Total number of stuck pipeline detections by org, pipeline, and severity',
      labelNames: ['org', 'pipeline', 'severity'],
      registers: [registry],
    }),

    detectionLatencySeconds: new Histogram({
      name: 'detection_latency_seconds',
      help: 'Time from pipeline start to stuck detection in seconds',
      labelNames: ['org'],
      buckets: [1, 5, 10, 30, 60, 120, 300],
      registers: [registry],
    }),

    falsePositiveRate1h: new Gauge({
      name: 'false_positive_rate_1h',
      help: 'Rolling 1-hour false positive rate (0-1) for stuck pipeline detections',
      labelNames: ['org'],
      registers: [registry],
    }),

    activeMonitoredPipelines: new Gauge({
      name: 'active_monitored_pipelines',
      help: 'Number of pipelines currently being actively monitored',
      labelNames: ['org'],
      registers: [registry],
    }),

    alertDeliveryLatencySeconds: new Histogram({
      name: 'alert_delivery_latency_seconds',
      help: 'Time from alert creation to successful delivery in seconds',
      labelNames: ['org', 'channel'],
      buckets: [1, 5, 10, 30, 60, 120],
      registers: [registry],
    }),
  };
}

let _businessMetrics: BusinessMetrics | undefined;

export function getBusinessMetrics(): BusinessMetrics {
  if (_businessMetrics === undefined) {
    _businessMetrics = createBusinessMetrics(getSharedRegistry());
  }
  return _businessMetrics;
}
