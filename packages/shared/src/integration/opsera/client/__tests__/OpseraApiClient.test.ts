/**
 * Unit tests for OpseraApiClient.
 *
 * HTTP calls are mocked via jest.fn() — no real network traffic.
 * Tests cover: each CRUD method, pagination, retry (429/500/503),
 * error parsing (404/409/400), and auth header injection.
 */

import { jest } from '@jest/globals';
import { OpseraApiClient } from '../OpseraApiClient.js';
import { OpseraAuthService } from '../../auth/OpseraAuthService.js';
import { OpseraApiError, OpseraAuthError } from '../OpseraApiError.js';
import type { Pipeline, PipelineRun, ToolRegistryEntry } from '../types.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makeJsonResponse(
  status: number,
  body: unknown,
  headers?: Record<string, string>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

const SAMPLE_PIPELINE: Pipeline = {
  id: 'pipeline-001',
  name: 'Test Pipeline',
  orgId: 'org-123',
  status: 'success' as Pipeline['status'],
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-01T01:00:00Z',
  config: { steps: [] },
};

const SAMPLE_RUN: PipelineRun = {
  runId: 'run-abc',
  pipelineId: 'pipeline-001',
  status: 'running' as PipelineRun['status'],
  startedAt: '2024-01-15T12:00:00Z',
};

function buildClient(fetchMock?: jest.MockedFunction<typeof global.fetch>): {
  client: OpseraApiClient;
  mockFetch: jest.MockedFunction<typeof global.fetch>;
} {
  const mockFetch = fetchMock ?? jest.fn<typeof global.fetch>();
  global.fetch = mockFetch;

  const authService = new OpseraAuthService({
    authMode: 'apikey',
    apiKey: 'test-api-key',
  });

  const client = new OpseraApiClient(authService, {
    baseUrl: 'https://api.opsera.io',
  });

  return { client, mockFetch };
}

// ─── Setup / Teardown ─────────────────────────────────────────────────────────

beforeEach(() => {
  jest.useFakeTimers({ advanceTimers: false });
});

afterEach(() => {
  jest.runAllTimers();
  jest.useRealTimers();
  jest.restoreAllMocks();
});

// ─── Auth header injection ─────────────────────────────────────────────────────

describe('OpseraApiClient — auth header injection', () => {
  it('injects x-api-key header on every request', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_PIPELINE));

    await client.getPipeline('pipeline-001');

    const [, init] = mockFetch.mock.calls[0]!;
    const reqHeaders = (init as RequestInit).headers as Record<string, string>;
    expect(reqHeaders['x-api-key']).toBe('test-api-key');
  });

  it('injects X-Correlation-ID header', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_PIPELINE));

    await client.getPipeline('pipeline-001');

    const [, init] = mockFetch.mock.calls[0]!;
    const reqHeaders = (init as RequestInit).headers as Record<string, string>;
    expect(reqHeaders['X-Correlation-ID']).toBeDefined();
    expect(typeof reqHeaders['X-Correlation-ID']).toBe('string');
  });
});

// ─── CRUD methods ─────────────────────────────────────────────────────────────

describe('OpseraApiClient — getPipeline', () => {
  it('calls GET /api/v1/pipelines/:id', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_PIPELINE));

    const result = await client.getPipeline('pipeline-001');

    expect(result.id).toBe('pipeline-001');
    const [url] = mockFetch.mock.calls[0]!;
    expect(String(url)).toContain('/api/v1/pipelines/pipeline-001');
    expect((mockFetch.mock.calls[0]![1] as RequestInit).method).toBe('GET');
  });

  it('URL-encodes pipeline IDs with special characters', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_PIPELINE));

    await client.getPipeline('pipe/line#001');
    const [url] = mockFetch.mock.calls[0]!;
    expect(String(url)).not.toContain('/pipe/line#001');
    expect(String(url)).toContain(encodeURIComponent('pipe/line#001'));
  });
});

describe('OpseraApiClient — createPipeline', () => {
  it('calls POST /api/v1/pipelines with the config body', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(201, SAMPLE_PIPELINE));

    const config = { steps: [], timeout: 1800 };
    await client.createPipeline(config);

    const [url, init] = mockFetch.mock.calls[0]!;
    expect(String(url)).toContain('/api/v1/pipelines');
    expect((init as RequestInit).method).toBe('POST');
    expect(JSON.parse((init as RequestInit).body as string)).toMatchObject(config);
  });
});

describe('OpseraApiClient — updatePipeline', () => {
  it('calls PUT /api/v1/pipelines/:id with the config body', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_PIPELINE));

    const config = { steps: [], timeout: 900 };
    await client.updatePipeline('pipeline-001', config);

    const [url, init] = mockFetch.mock.calls[0]!;
    expect(String(url)).toContain('/api/v1/pipelines/pipeline-001');
    expect((init as RequestInit).method).toBe('PUT');
  });
});

describe('OpseraApiClient — deletePipeline', () => {
  it('calls DELETE /api/v1/pipelines/:id and returns void', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(204, null));

    const result = await client.deletePipeline('pipeline-001');
    expect(result).toBeUndefined();

    const [url, init] = mockFetch.mock.calls[0]!;
    expect(String(url)).toContain('/api/v1/pipelines/pipeline-001');
    expect((init as RequestInit).method).toBe('DELETE');
  });
});

describe('OpseraApiClient — triggerPipeline', () => {
  it('calls POST /api/v1/pipelines/:id/trigger with params', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(202, SAMPLE_RUN));

    const params = { branch: 'main', environment: 'production' };
    const run = await client.triggerPipeline('pipeline-001', params);

    expect(run.runId).toBe('run-abc');
    const [url, init] = mockFetch.mock.calls[0]!;
    expect(String(url)).toContain('/api/v1/pipelines/pipeline-001/trigger');
    expect((init as RequestInit).method).toBe('POST');
    expect(JSON.parse((init as RequestInit).body as string)).toMatchObject(params);
  });
});

describe('OpseraApiClient — getPipelineStatus', () => {
  it('calls GET /api/v1/pipelines/:id/runs/:runId', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_RUN));

    const run = await client.getPipelineStatus('pipeline-001', 'run-abc');
    expect(run.runId).toBe('run-abc');

    const [url] = mockFetch.mock.calls[0]!;
    expect(String(url)).toContain('/api/v1/pipelines/pipeline-001/runs/run-abc');
  });
});

describe('OpseraApiClient — getToolRegistry', () => {
  it('calls GET /api/v1/tools and returns the array', async () => {
    const { client, mockFetch } = buildClient();
    const tools: ToolRegistryEntry[] = [
      { id: 'tool-1', name: 'Git', type: 'git', version: '2.44', capabilities: ['clone'] },
    ];
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, tools));

    const result = await client.getToolRegistry();
    expect(result).toHaveLength(1);
    expect(result[0]?.name).toBe('Git');
  });
});

// ─── Pagination ───────────────────────────────────────────────────────────────

describe('OpseraApiClient — listPipelines pagination', () => {
  it('collects all pages (cursor-based) and yields each pipeline', async () => {
    const { client, mockFetch } = buildClient();

    const page1 = {
      data: [{ ...SAMPLE_PIPELINE, id: 'p-1' }, { ...SAMPLE_PIPELINE, id: 'p-2' }],
      total: 3,
      hasMore: true,
      nextCursor: 'cursor-abc',
    };
    const page2 = {
      data: [{ ...SAMPLE_PIPELINE, id: 'p-3' }],
      total: 3,
      hasMore: false,
      nextCursor: null,
    };

    mockFetch
      .mockResolvedValueOnce(makeJsonResponse(200, page1))
      .mockResolvedValueOnce(makeJsonResponse(200, page2));

    const collected: string[] = [];
    for await (const pipeline of client.listPipelines()) {
      collected.push(pipeline.id);
    }

    expect(collected).toEqual(['p-1', 'p-2', 'p-3']);
    expect(mockFetch).toHaveBeenCalledTimes(2);

    // Second call should include cursor param
    const [url2] = mockFetch.mock.calls[1]!;
    expect(String(url2)).toContain('cursor=cursor-abc');
  });

  it('handles offset-based pagination (no cursor)', async () => {
    const { client, mockFetch } = buildClient();

    const page1 = { data: [{ ...SAMPLE_PIPELINE, id: 'p-1' }], total: 2, hasMore: true };
    const page2 = { data: [{ ...SAMPLE_PIPELINE, id: 'p-2' }], total: 2, hasMore: false };

    mockFetch
      .mockResolvedValueOnce(makeJsonResponse(200, page1))
      .mockResolvedValueOnce(makeJsonResponse(200, page2));

    const ids: string[] = [];
    for await (const p of client.listPipelines()) {
      ids.push(p.id);
    }

    expect(ids).toEqual(['p-1', 'p-2']);
    const [url2] = mockFetch.mock.calls[1]!;
    expect(String(url2)).toContain('page=2');
  });

  it('returns empty array without errors when no pipelines exist', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(
      makeJsonResponse(200, { data: [], total: 0, hasMore: false }),
    );

    const results: Pipeline[] = [];
    for await (const p of client.listPipelines()) {
      results.push(p);
    }
    expect(results).toHaveLength(0);
  });

  it('applies filter parameters to the list request', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(
      makeJsonResponse(200, { data: [], total: 0, hasMore: false }),
    );

    for await (const _ of client.listPipelines({ status: 'running' as Pipeline['status'], owner: 'alice' })) {
      // drain
    }

    const [url] = mockFetch.mock.calls[0]!;
    expect(String(url)).toContain('status=running');
    expect(String(url)).toContain('owner=alice');
  });
});

// ─── Retry behaviour ──────────────────────────────────────────────────────────

describe('OpseraApiClient — retry logic', () => {
  it('retries 429 responses and honours Retry-After header', async () => {
    jest.useRealTimers();
    const { client, mockFetch } = buildClient();

    mockFetch
      .mockResolvedValueOnce(
        makeJsonResponse(429, { code: 'RATE_LIMIT_EXCEEDED' }, { 'Retry-After': '0' }),
      )
      .mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_PIPELINE));

    const result = await client.getPipeline('p-1');
    expect(result.id).toBe('pipeline-001');
    expect(mockFetch).toHaveBeenCalledTimes(2);
  }, 10_000);

  it('retries 503 transient errors up to MAX_RETRIES times', async () => {
    jest.useRealTimers();
    const { client, mockFetch } = buildClient();

    // 3 failures then 1 success
    mockFetch
      .mockResolvedValueOnce(makeJsonResponse(503, {}))
      .mockResolvedValueOnce(makeJsonResponse(503, {}))
      .mockResolvedValueOnce(makeJsonResponse(503, {}))
      .mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_PIPELINE));

    const result = await client.getPipeline('p-1');
    expect(result.id).toBe('pipeline-001');
    expect(mockFetch).toHaveBeenCalledTimes(4);
  }, 30_000);

  it('throws SERVER_ERROR after exhausting all retries for 500', async () => {
    jest.useRealTimers();
    const { client, mockFetch } = buildClient();

    mockFetch.mockResolvedValue(makeJsonResponse(500, {}));

    await expect(client.getPipeline('p-1')).rejects.toMatchObject({
      code: 'SERVER_ERROR',
      isRetryable: true,
    });
    // initial + 3 retries = 4 calls
    expect(mockFetch).toHaveBeenCalledTimes(4);
  }, 30_000);
});

// ─── Error parsing ────────────────────────────────────────────────────────────

describe('OpseraApiClient — error parsing', () => {
  it('parses 404 into OpseraApiError with PIPELINE_NOT_FOUND', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(
      makeJsonResponse(404, { code: 'PIPELINE_NOT_FOUND', message: 'Pipeline not found' }),
    );

    await expect(client.getPipeline('missing')).rejects.toMatchObject({
      code: 'PIPELINE_NOT_FOUND',
      statusCode: 404,
      isRetryable: false,
    });
  });

  it('parses 409 into OpseraApiError with PIPELINE_ALREADY_RUNNING', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(
      makeJsonResponse(409, {
        code: 'PIPELINE_ALREADY_RUNNING',
        message: 'Already running',
      }),
    );

    await expect(client.triggerPipeline('p-1')).rejects.toMatchObject({
      code: 'PIPELINE_ALREADY_RUNNING',
      statusCode: 409,
    });
  });

  it('parses 401 into OpseraAuthError with AUTH_INVALID_KEY', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(
      makeJsonResponse(401, { message: 'Invalid API key' }),
    );

    const err = await client.getPipeline('p-1').catch((e: unknown) => e);
    expect(err).toBeInstanceOf(OpseraAuthError);
    expect((err as OpseraAuthError).code).toBe('AUTH_INVALID_KEY');
    expect((err as OpseraAuthError).remediationMessage).toBeDefined();
  });

  it('includes request context (method, path, correlationId) in errors', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(404, { message: 'not found' }));

    const err = await client.getPipeline('p-1').catch((e: unknown) => e);
    expect((err as OpseraApiError).requestContext?.method).toBe('GET');
    expect((err as OpseraApiError).requestContext?.path).toContain('/api/v1/pipelines');
  });

  it('wraps non-JSON 500 response in OpseraApiError', async () => {
    jest.useRealTimers();
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValue(new Response('Internal Server Error', { status: 500 }));

    await expect(client.getPipeline('p-1')).rejects.toBeInstanceOf(OpseraApiError);
  }, 30_000);

  it('throws OpseraApiError with NETWORK_ERROR on fetch rejection (after retries)', async () => {
    jest.useRealTimers();
    const { client, mockFetch } = buildClient();
    mockFetch.mockRejectedValue(new TypeError('Failed to fetch'));

    await expect(client.getPipeline('p-1')).rejects.toMatchObject({
      code: 'NETWORK_ERROR',
    });
  }, 30_000);
});

// ─── OpseraApiError type guard ────────────────────────────────────────────────

describe('isOpseraApiError / isOpseraAuthError', () => {
  it('isOpseraApiError returns true for OpseraApiError instances', () => {
    const { isOpseraApiError } = require('../OpseraApiError.js') as typeof import('../OpseraApiError.js');
    const err = new OpseraApiError('msg', 'CODE', 400, false);
    expect(isOpseraApiError(err)).toBe(true);
    expect(isOpseraApiError(new Error('plain'))).toBe(false);
  });
});
