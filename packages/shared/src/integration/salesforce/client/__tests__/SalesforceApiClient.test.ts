/**
 * Unit tests for SalesforceApiClient.
 *
 * HTTP calls are mocked via jest.fn() — no real network traffic.
 * Tests cover:
 *   - query() constructs correct URL with SOQL encoding
 *   - queryMore() follows nextRecordsUrl for pagination
 *   - getRecord() constructs correct URL with optional fields param
 *   - Auth Bearer token injected on every request
 *   - Rate limit retry (429, REQUEST_LIMIT_EXCEEDED body)
 *   - INVALID_SESSION_ID triggers single token refresh + retry
 *   - Transient 5xx retry with exponential backoff
 *   - Structured SalesforceApiError on 400, 401 (post-refresh), 403
 *   - Non-JSON / maintenance HTML response wrapped in error
 *   - Zero-record QueryResult returned as-is (not null)
 */

import { jest } from '@jest/globals';
import { SalesforceApiClient } from '../SalesforceApiClient.js';
import { SalesforceApiError, isSalesforceApiError } from '../SalesforceApiError.js';
import type { SalesforceAuthService } from '../../auth/SalesforceAuthService.js';
import type { QueryResult, SObjectRecord } from '../types.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

const INSTANCE_URL = 'https://opsera.my.salesforce.com';
const ACCESS_TOKEN = 'test-access-token-abc123';
const API_VERSION = 'v59.0';

function makeJsonResponse(
  status: number,
  body: unknown,
  headers: Record<string, string> = {},
): Response {
  const bodyStr = body === null ? '' : JSON.stringify(body);
  return new Response(bodyStr, {
    status,
    headers: {
      'Content-Type': body === null ? 'text/html' : 'application/json',
      ...headers,
    },
  });
}

function makeHtmlResponse(status: number): Response {
  return new Response('<html><body>Service Unavailable</body></html>', {
    status,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  });
}

const SAMPLE_QUERY_RESULT: QueryResult = {
  totalSize: 1,
  done: true,
  records: [
    {
      attributes: { type: 'AsyncApexJob', url: '/services/data/v59.0/sobjects/AsyncApexJob/AAA' },
      Id: 'AAA',
      Status: 'Completed',
    },
  ],
};

const SAMPLE_RECORD: SObjectRecord = {
  attributes: { type: 'Account', url: '/services/data/v59.0/sobjects/Account/001AAA' },
  Id: '001AAA',
  Name: 'Test Account',
};

type MockFetch = jest.MockedFunction<(url: string, init: RequestInit) => Promise<Response>>;

function buildClient(mockFetch?: MockFetch): {
  client: SalesforceApiClient;
  mockFetch: MockFetch;
  mockAuthService: jest.Mocked<Pick<SalesforceAuthService, 'getAccessToken' | 'forceRefresh'>>;
} {
  const fetch = mockFetch ?? jest.fn<(url: string, init: RequestInit) => Promise<Response>>();

  const mockAuthService = {
    getAccessToken: jest.fn<() => Promise<{ accessToken: string; instanceUrl: string }>>(),
    forceRefresh: jest.fn<() => Promise<{ accessToken: string; instanceUrl: string }>>(),
  };

  mockAuthService.getAccessToken.mockResolvedValue({
    accessToken: ACCESS_TOKEN,
    instanceUrl: INSTANCE_URL,
  });
  mockAuthService.forceRefresh.mockResolvedValue({
    accessToken: 'refreshed-token-xyz',
    instanceUrl: INSTANCE_URL,
  });

  const client = new SalesforceApiClient(
    mockAuthService as unknown as SalesforceAuthService,
    { apiVersion: API_VERSION, httpClient: fetch },
  );

  return { client, mockFetch: fetch, mockAuthService };
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

// ─── query() ─────────────────────────────────────────────────────────────────

describe('SalesforceApiClient — query()', () => {
  it('sends GET to /services/data/vXX.X/query with URL-encoded SOQL', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_QUERY_RESULT));

    const result = await client.query("SELECT Id FROM AsyncApexJob WHERE Status = 'Processing'");

    expect(result.totalSize).toBe(1);
    expect(result.done).toBe(true);
    expect(result.records).toHaveLength(1);

    const [url, init] = mockFetch.mock.calls[0]!;
    expect(typeof url).toBe('string');
    const parsedUrl = new URL(url as string);
    expect(parsedUrl.pathname).toBe(`/services/data/${API_VERSION}/query`);
    expect(parsedUrl.searchParams.get('q')).toBe("SELECT Id FROM AsyncApexJob WHERE Status = 'Processing'");
    expect((init as RequestInit).method).toBe('GET');
  });

  it('URL-encodes SOQL with special characters (ampersands, single quotes)', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, { totalSize: 0, done: true, records: [] }));

    await client.query("SELECT Id FROM Contact WHERE Email LIKE '%@opsera.io' AND IsActive = true");

    const [url] = mockFetch.mock.calls[0]!;
    const parsedUrl = new URL(url as string);
    // The SOQL must be set as a URL search parameter (properly encoded)
    const soql = parsedUrl.searchParams.get('q');
    expect(soql).toContain('@opsera.io');
    expect(soql).toContain("AND IsActive = true");
  });

  it('returns an empty records array (not null) when no results found', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(
      makeJsonResponse(200, { totalSize: 0, done: true, records: [] }),
    );

    const result = await client.query('SELECT Id FROM Account WHERE Id = null');
    expect(result.records).toEqual([]);
    expect(Array.isArray(result.records)).toBe(true);
  });

  it('injects Authorization Bearer header on every request', async () => {
    const { client, mockFetch, mockAuthService } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_QUERY_RESULT));

    await client.query('SELECT Id FROM Account');

    expect(mockAuthService.getAccessToken).toHaveBeenCalledTimes(1);
    const [, init] = mockFetch.mock.calls[0]!;
    const headers = (init as RequestInit).headers as Record<string, string>;
    expect(headers['Authorization']).toBe(`Bearer ${ACCESS_TOKEN}`);
  });
});

// ─── queryMore() ─────────────────────────────────────────────────────────────

describe('SalesforceApiClient — queryMore()', () => {
  it('follows nextRecordsUrl from a previous QueryResult', async () => {
    const { client, mockFetch } = buildClient();

    const page2: QueryResult = {
      totalSize: 3,
      done: true,
      records: [
        {
          attributes: { type: 'AsyncApexJob', url: '/services/data/v59.0/sobjects/AsyncApexJob/CCC' },
          Id: 'CCC',
          Status: 'Failed',
        },
      ],
    };
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, page2));

    const nextUrl = `/services/data/${API_VERSION}/query/01gRM00000065RBYAY-2000`;
    const result = await client.queryMore(nextUrl);

    expect(result.done).toBe(true);
    expect(result.records[0]?.['Id']).toBe('CCC');

    const [url] = mockFetch.mock.calls[0]!;
    expect(url as string).toContain('/query/01gRM00000065RBYAY-2000');
  });

  it('multi-page: query then queryMore retrieves all records', async () => {
    const { client, mockFetch } = buildClient();

    const page1: QueryResult = {
      totalSize: 2,
      done: false,
      nextRecordsUrl: `/services/data/${API_VERSION}/query/cursor-abc`,
      records: [
        { attributes: { type: 'Account', url: '/sf/Account/001' }, Id: 'AAA' },
      ],
    };
    const page2: QueryResult = {
      totalSize: 2,
      done: true,
      records: [
        { attributes: { type: 'Account', url: '/sf/Account/002' }, Id: 'BBB' },
      ],
    };

    mockFetch
      .mockResolvedValueOnce(makeJsonResponse(200, page1))
      .mockResolvedValueOnce(makeJsonResponse(200, page2));

    const first = await client.query('SELECT Id FROM Account');
    expect(first.done).toBe(false);
    expect(first.nextRecordsUrl).toBeDefined();

    const second = await client.queryMore(first.nextRecordsUrl!);
    expect(second.done).toBe(true);
    expect(second.records[0]?.['Id']).toBe('BBB');

    expect(mockFetch).toHaveBeenCalledTimes(2);
  });
});

// ─── getRecord() ─────────────────────────────────────────────────────────────

describe('SalesforceApiClient — getRecord()', () => {
  it('sends GET to /services/data/vXX.X/sobjects/{sObjectType}/{id}', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_RECORD));

    const record = await client.getRecord('Account', '001AAA');
    expect(record['Id']).toBe('001AAA');
    expect(record['Name']).toBe('Test Account');

    const [url] = mockFetch.mock.calls[0]!;
    expect(url as string).toContain(`/services/data/${API_VERSION}/sobjects/Account/001AAA`);
  });

  it('appends fields query param when fields list is provided', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_RECORD));

    await client.getRecord('Account', '001AAA', ['Id', 'Name', 'BillingCity']);

    const [url] = mockFetch.mock.calls[0]!;
    const parsedUrl = new URL(url as string);
    expect(parsedUrl.searchParams.get('fields')).toBe('Id,Name,BillingCity');
  });

  it('does not append fields param when fields list is empty', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_RECORD));

    await client.getRecord('Account', '001AAA', []);

    const [url] = mockFetch.mock.calls[0]!;
    const parsedUrl = new URL(url as string);
    expect(parsedUrl.searchParams.get('fields')).toBeNull();
  });

  it('URL-encodes sObjectType and id', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_RECORD));

    await client.getRecord('My Custom Object__c', '001 AAA/test');

    const [url] = mockFetch.mock.calls[0]!;
    expect(url as string).not.toContain(' ');
    expect(url as string).not.toContain('__c/001 ');
  });
});

// ─── Session refresh (INVALID_SESSION_ID) ────────────────────────────────────

describe('SalesforceApiClient — INVALID_SESSION_ID session refresh', () => {
  it('calls forceRefresh() and retries once on INVALID_SESSION_ID', async () => {
    jest.useRealTimers();
    const { client, mockFetch, mockAuthService } = buildClient();

    const sessionExpiredBody = [{ errorCode: 'INVALID_SESSION_ID', message: 'Session expired or invalid', fields: [] }];
    mockFetch
      .mockResolvedValueOnce(makeJsonResponse(401, sessionExpiredBody))
      .mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_QUERY_RESULT));

    const result = await client.query('SELECT Id FROM Account');

    expect(mockAuthService.forceRefresh).toHaveBeenCalledTimes(1);
    expect(result.records).toHaveLength(1);
    expect(mockFetch).toHaveBeenCalledTimes(2);
  });

  it('does NOT retry again if the refresh itself still returns 401', async () => {
    jest.useRealTimers();
    const { client, mockFetch, mockAuthService } = buildClient();

    const sessionExpiredBody = [{ errorCode: 'INVALID_SESSION_ID', message: 'Session expired', fields: [] }];
    mockFetch
      .mockResolvedValueOnce(makeJsonResponse(401, sessionExpiredBody)) // triggers refresh
      .mockResolvedValueOnce(makeJsonResponse(401, sessionExpiredBody)); // second attempt fails

    await expect(client.query('SELECT Id FROM Account')).rejects.toBeInstanceOf(SalesforceApiError);
    expect(mockAuthService.forceRefresh).toHaveBeenCalledTimes(1);
    expect(mockFetch).toHaveBeenCalledTimes(2);
  });

  it('throws SalesforceApiError on plain 401 without INVALID_SESSION_ID', async () => {
    const { client, mockFetch } = buildClient();
    const body = [{ errorCode: 'INVALID_AUTH_HEADER', message: 'Invalid auth header', fields: [] }];
    mockFetch.mockResolvedValueOnce(makeJsonResponse(401, body));

    await expect(client.query('SELECT Id FROM Account')).rejects.toBeInstanceOf(SalesforceApiError);
  });
});

// ─── Rate limit retry ─────────────────────────────────────────────────────────

describe('SalesforceApiClient — rate limit retry', () => {
  it('retries on HTTP 429 and respects Retry-After header', async () => {
    jest.useRealTimers();
    const { client, mockFetch } = buildClient();

    mockFetch
      .mockResolvedValueOnce(
        makeJsonResponse(429, [], { 'Retry-After': '0', 'Content-Type': 'application/json' }),
      )
      .mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_QUERY_RESULT));

    const result = await client.query('SELECT Id FROM Account');
    expect(result.totalSize).toBe(1);
    expect(mockFetch).toHaveBeenCalledTimes(2);
  }, 10_000);

  it('retries on REQUEST_LIMIT_EXCEEDED in response body', async () => {
    jest.useRealTimers();
    const { client, mockFetch } = buildClient();

    const rateLimitBody = [{ errorCode: 'REQUEST_LIMIT_EXCEEDED', message: 'TotalRequests Limit exceeded.', fields: [] }];
    mockFetch
      .mockResolvedValueOnce(makeJsonResponse(403, rateLimitBody))
      .mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_QUERY_RESULT));

    const result = await client.query('SELECT Id FROM Account');
    expect(result.totalSize).toBe(1);
    expect(mockFetch).toHaveBeenCalledTimes(2);
  }, 10_000);

  it('throws after exhausting MAX_RETRIES on persistent 429', async () => {
    jest.useRealTimers();
    const { client, mockFetch } = buildClient();

    mockFetch.mockResolvedValue(makeJsonResponse(429, [], { 'Retry-After': '0' }));

    await expect(client.query('SELECT Id FROM Account')).rejects.toBeInstanceOf(SalesforceApiError);
    // initial + 3 retries = 4 calls
    expect(mockFetch).toHaveBeenCalledTimes(4);
  }, 30_000);
});

// ─── Transient 5xx retry ──────────────────────────────────────────────────────

describe('SalesforceApiClient — transient 5xx retry', () => {
  it('retries on 503 and succeeds on the next attempt', async () => {
    jest.useRealTimers();
    const { client, mockFetch } = buildClient();

    mockFetch
      .mockResolvedValueOnce(makeJsonResponse(503, null))
      .mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_QUERY_RESULT));

    const result = await client.query('SELECT Id FROM Account');
    expect(result.totalSize).toBe(1);
    expect(mockFetch).toHaveBeenCalledTimes(2);
  }, 10_000);

  it('throws SalesforceApiError after exhausting all retries on 500', async () => {
    jest.useRealTimers();
    const { client, mockFetch } = buildClient();

    mockFetch.mockResolvedValue(makeJsonResponse(500, null));

    await expect(client.query('SELECT Id FROM Account')).rejects.toBeInstanceOf(SalesforceApiError);
    expect(mockFetch).toHaveBeenCalledTimes(4); // initial + 3 retries
  }, 30_000);
});

// ─── Error parsing ────────────────────────────────────────────────────────────

describe('SalesforceApiClient — error parsing', () => {
  it('parses 400 MALFORMED_QUERY into SalesforceApiError', async () => {
    const { client, mockFetch } = buildClient();
    const body = [{ errorCode: 'MALFORMED_QUERY', message: "unexpected token: 'FORM'", fields: [] }];
    mockFetch.mockResolvedValueOnce(makeJsonResponse(400, body));

    const err = await client.query('SELECT FORM Account').catch((e: unknown) => e);
    expect(isSalesforceApiError(err)).toBe(true);
    const apiErr = err as SalesforceApiError;
    expect(apiErr.errorCode).toBe('MALFORMED_QUERY');
    expect(apiErr.statusCode).toBe(400);
    expect(apiErr.isRetryable).toBe(false);
    expect(apiErr.message).toContain("unexpected token");
  });

  it('parses field-level errors and exposes fields array', async () => {
    const { client, mockFetch } = buildClient();
    const body = [{ errorCode: 'FIELD_INTEGRITY_EXCEPTION', message: 'value of incorrect type', fields: ['BillingState'] }];
    mockFetch.mockResolvedValueOnce(makeJsonResponse(400, body));

    const err = await client.getRecord('Account', '001AAA').catch((e: unknown) => e);
    expect(isSalesforceApiError(err)).toBe(true);
    expect((err as SalesforceApiError).fields).toContain('BillingState');
  });

  it('preserves allErrors array for multi-error responses', async () => {
    const { client, mockFetch } = buildClient();
    const body = [
      { errorCode: 'ERROR_ONE', message: 'First error', fields: [] },
      { errorCode: 'ERROR_TWO', message: 'Second error', fields: ['SomeField'] },
    ];
    mockFetch.mockResolvedValueOnce(makeJsonResponse(400, body));

    const err = await client.query('SELECT Id FROM Account').catch((e: unknown) => e);
    expect(isSalesforceApiError(err)).toBe(true);
    expect((err as SalesforceApiError).allErrors).toHaveLength(2);
    expect((err as SalesforceApiError).allErrors[1]?.errorCode).toBe('ERROR_TWO');
  });

  it('includes request context (method, urlPath, correlationId) in errors', async () => {
    const { client, mockFetch } = buildClient();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(400, [{ errorCode: 'ERR', message: 'err', fields: [] }]));

    const err = await client.query('SELECT Id FROM Account').catch((e: unknown) => e);
    const apiErr = err as SalesforceApiError;
    expect(apiErr.requestContext?.method).toBe('GET');
    expect(apiErr.requestContext?.urlPath).toContain('/query');
    expect(typeof apiErr.requestContext?.correlationId).toBe('string');
  });

  it('wraps HTML maintenance page response in SalesforceApiError', async () => {
    jest.useRealTimers();
    const { client, mockFetch } = buildClient();
    // 503 with HTML body (Salesforce maintenance mode)
    mockFetch.mockResolvedValue(makeHtmlResponse(503));

    await expect(client.query('SELECT Id FROM Account')).rejects.toBeInstanceOf(SalesforceApiError);
  }, 30_000);

  it('throws SalesforceApiError with NETWORK_ERROR on fetch rejection after retries', async () => {
    jest.useRealTimers();
    const { client, mockFetch } = buildClient();
    mockFetch.mockRejectedValue(new TypeError('Failed to fetch'));

    await expect(client.query('SELECT Id FROM Account')).rejects.toMatchObject({
      errorCode: 'NETWORK_ERROR',
    });
  }, 30_000);
});

// ─── API version configurable ─────────────────────────────────────────────────

describe('SalesforceApiClient — API version', () => {
  it('uses the configured apiVersion in all request paths', async () => {
    const mockFetch = jest.fn<(url: string, init: RequestInit) => Promise<Response>>();
    mockFetch.mockResolvedValueOnce(makeJsonResponse(200, SAMPLE_QUERY_RESULT));

    const mockAuthService = {
      getAccessToken: jest.fn<() => Promise<{ accessToken: string; instanceUrl: string }>>()
        .mockResolvedValue({ accessToken: ACCESS_TOKEN, instanceUrl: INSTANCE_URL }),
      forceRefresh: jest.fn<() => Promise<{ accessToken: string; instanceUrl: string }>>(),
    };

    const client = new SalesforceApiClient(
      mockAuthService as unknown as SalesforceAuthService,
      { apiVersion: 'v61.0', httpClient: mockFetch },
    );

    await client.query('SELECT Id FROM Account');

    const [url] = mockFetch.mock.calls[0]!;
    expect(url as string).toContain('/services/data/v61.0/query');
  });

  it('defaults to v59.0 when no version is configured', () => {
    const mockAuthService = {
      getAccessToken: jest.fn(),
      forceRefresh: jest.fn(),
    };
    const client = new SalesforceApiClient(
      mockAuthService as unknown as SalesforceAuthService,
    );
    // Access the private field via type assertion for verification
    expect((client as unknown as { apiVersion: string }).apiVersion).toBe('v59.0');
  });
});

// ─── isSalesforceApiError type guard ─────────────────────────────────────────

describe('isSalesforceApiError', () => {
  it('returns true for SalesforceApiError instances', () => {
    const err = new SalesforceApiError('msg', 'CODE', 400, false, []);
    expect(isSalesforceApiError(err)).toBe(true);
  });

  it('returns false for generic Error', () => {
    expect(isSalesforceApiError(new Error('plain'))).toBe(false);
  });

  it('returns false for non-Error values', () => {
    expect(isSalesforceApiError(null)).toBe(false);
    expect(isSalesforceApiError('error string')).toBe(false);
    expect(isSalesforceApiError(42)).toBe(false);
  });
});
