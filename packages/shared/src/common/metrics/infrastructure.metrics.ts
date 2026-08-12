import { Counter, Gauge, Histogram, type Registry } from 'prom-client';
import { getSharedRegistry } from './registry.js';

export interface InfrastructureMetrics {
  pgConnectionsActive: Gauge;
  pgQueryDurationSeconds: Histogram<'operation'>;
  redisMemoryUsedBytes: Gauge;
  redisStreamsConsumerLag: Gauge<'stream'>;
  redisStreamsMessagesProcessedTotal: Counter<'stream'>;
}

export function createInfrastructureMetrics(registry: Registry): InfrastructureMetrics {
  return {
    pgConnectionsActive: new Gauge({
      name: 'pg_connections_active',
      help: 'Number of active PostgreSQL connections in the connection pool',
      registers: [registry],
    }),

    pgQueryDurationSeconds: new Histogram({
      name: 'pg_query_duration_seconds',
      help: 'PostgreSQL query execution duration in seconds',
      labelNames: ['operation'],
      buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5],
      registers: [registry],
    }),

    redisMemoryUsedBytes: new Gauge({
      name: 'redis_memory_used_bytes',
      help: 'Redis RSS memory usage in bytes',
      registers: [registry],
    }),

    redisStreamsConsumerLag: new Gauge({
      name: 'redis_streams_consumer_lag',
      help: 'Number of pending unacknowledged messages in a Redis Streams consumer group',
      labelNames: ['stream'],
      registers: [registry],
    }),

    redisStreamsMessagesProcessedTotal: new Counter({
      name: 'redis_streams_messages_processed_total',
      help: 'Total messages successfully processed from Redis Streams',
      labelNames: ['stream'],
      registers: [registry],
    }),
  };
}

let _infrastructureMetrics: InfrastructureMetrics | undefined;

export function getInfrastructureMetrics(): InfrastructureMetrics {
  if (_infrastructureMetrics === undefined) {
    _infrastructureMetrics = createInfrastructureMetrics(getSharedRegistry());
  }
  return _infrastructureMetrics;
}
