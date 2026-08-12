import { jest } from '@jest/globals';
import { createHealthRouter } from '../routes.js';
import { HealthStatus } from '../types.js';
import type { AggregateHealth, ConnectorHealth } from '../types.js';
import type { ConnectorStatusMonitor } from '../ConnectorStatusMonitor.js';
import { createMockRequest, createMockResponse } from '../../../database/test-utils.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makeAggregate(
  status: HealthStatus,
  overrides?: Partial<Record<string, ConnectorHealth>>,
): AggregateHealth {
  const checkedAt = '2024-01-15T12:00:00.000Z';
  const sf: ConnectorHealth = {
    name: 'salesforce',
    status: HealthStatus.HEALTHY,
    authStatus: 'authenticated',
    apiReachable: true,
    checkedAt,
  };
  const ops: ConnectorHealth = {
    name: 'opsera',
    status: HealthStatus.HEALTHY,
    authStatus: 'authenticated',
    apiReachable: true,
    checkedAt,
  };
  return {
    status,
    connectors: { salesforce: sf, opsera: ops, ...overrides },
    checkedAt,
  };
}

function makeMonitor(aggregate: AggregateHealth): jest.Mocked<
  Pick<ConnectorStatusMonitor, 'getAggregateHealth' | 'getConnectorHealth'>
> {
  return {
    getAggregateHealth: jest.fn<ConnectorStatusMonitor['getAggregateHealth']>().mockResolvedValue(aggregate),
    getConnectorHealth: jest.fn<ConnectorStatusMonitor['getConnectorHealth']>().mockImplementation(
      (name) => aggregate.connectors[name] ?? null,
    ),
  };
}

// Invoke a route handler from the router
async function invokeRoute(
  router: ReturnType<typeof createHealthRouter>,
  method: string,
  path: string,
): Promise<{ statusCode: number; body: unknown }> {
  const { res, getStatusCode, getJsonBody } = createMockResponse();
  const req = createMockRequest({ method, path });

  // Find matching route handler by simulating Express routing
  const layer = (router.stack as Array<{ route?: { path: string; methods: Record<string, boolean>; stack: Array<{ handle: (req: unknown, res: unknown, next: unknown) => void }> } }>)
    .find((l) => l.route?.path === path && l.route?.methods[method.toLowerCase()] === true);

  if (layer?.route === undefined) {
    throw new Error(`No route found for ${method} ${path}`);
  }

  const handle = layer.route.stack[0]!.handle;
  await new Promise<void>((resolve) => {
    handle(req, res, resolve);
    // Allow the async void IIFE inside the handler to complete
    setTimeout(resolve, 100);
  });

  return { statusCode: getStatusCode(), body: getJsonBody() };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('createHealthRouter', () => {
  describe('GET / (aggregate)', () => {
    it('returns 200 with aggregate when status is HEALTHY', async () => {
      const aggregate = makeAggregate(HealthStatus.HEALTHY);
      const monitor = makeMonitor(aggregate);
      const router = createHealthRouter(monitor as unknown as ConnectorStatusMonitor);

      const { statusCode, body } = await invokeRoute(router, 'GET', '/');

      expect(statusCode).toBe(200);
      expect((body as AggregateHealth).status).toBe(HealthStatus.HEALTHY);
    });

    it('returns 207 when aggregate is DEGRADED', async () => {
      const aggregate = makeAggregate(HealthStatus.DEGRADED);
      const monitor = makeMonitor(aggregate);
      const router = createHealthRouter(monitor as unknown as ConnectorStatusMonitor);

      const { statusCode } = await invokeRoute(router, 'GET', '/');
      expect(statusCode).toBe(207);
    });

    it('returns 503 when aggregate is UNHEALTHY', async () => {
      const aggregate = makeAggregate(HealthStatus.UNHEALTHY);
      const monitor = makeMonitor(aggregate);
      const router = createHealthRouter(monitor as unknown as ConnectorStatusMonitor);

      const { statusCode } = await invokeRoute(router, 'GET', '/');
      expect(statusCode).toBe(503);
    });

    it('returns 503 with unhealthy envelope when monitor throws', async () => {
      const monitor = {
        getAggregateHealth: jest.fn<ConnectorStatusMonitor['getAggregateHealth']>().mockRejectedValue(
          new Error('monitor exploded'),
        ),
        getConnectorHealth: jest.fn<ConnectorStatusMonitor['getConnectorHealth']>(),
      };
      const router = createHealthRouter(monitor as unknown as ConnectorStatusMonitor);

      const { statusCode, body } = await invokeRoute(router, 'GET', '/');
      expect(statusCode).toBe(503);
      expect((body as AggregateHealth).status).toBe(HealthStatus.UNHEALTHY);
    });
  });

  describe('GET /salesforce', () => {
    it('returns 200 when Salesforce connector is healthy', async () => {
      const aggregate = makeAggregate(HealthStatus.HEALTHY);
      const monitor = makeMonitor(aggregate);
      const router = createHealthRouter(monitor as unknown as ConnectorStatusMonitor);

      const { statusCode, body } = await invokeRoute(router, 'GET', '/salesforce');

      expect(statusCode).toBe(200);
      expect((body as ConnectorHealth).name).toBe('salesforce');
    });

    it('returns 503 when Salesforce connector is not registered', async () => {
      const aggregate: AggregateHealth = { status: HealthStatus.UNHEALTHY, connectors: {}, checkedAt: '' };
      const monitor = makeMonitor(aggregate);
      const router = createHealthRouter(monitor as unknown as ConnectorStatusMonitor);

      const { statusCode } = await invokeRoute(router, 'GET', '/salesforce');
      expect(statusCode).toBe(503);
    });
  });

  describe('GET /opsera', () => {
    it('returns 200 when Opsera connector is healthy', async () => {
      const aggregate = makeAggregate(HealthStatus.HEALTHY);
      const monitor = makeMonitor(aggregate);
      const router = createHealthRouter(monitor as unknown as ConnectorStatusMonitor);

      const { statusCode, body } = await invokeRoute(router, 'GET', '/opsera');

      expect(statusCode).toBe(200);
      expect((body as ConnectorHealth).name).toBe('opsera');
    });

    it('returns 207 when Opsera connector is degraded', async () => {
      const degradedOpsera: ConnectorHealth = {
        name: 'opsera',
        status: HealthStatus.DEGRADED,
        authStatus: 'authenticated',
        apiReachable: true,
        rateLimitRemaining: 5,
        checkedAt: '2024-01-15T12:00:00.000Z',
      };
      const aggregate = makeAggregate(HealthStatus.DEGRADED, { opsera: degradedOpsera });
      const monitor = makeMonitor(aggregate);
      const router = createHealthRouter(monitor as unknown as ConnectorStatusMonitor);

      const { statusCode } = await invokeRoute(router, 'GET', '/opsera');
      expect(statusCode).toBe(207);
    });
  });
});
