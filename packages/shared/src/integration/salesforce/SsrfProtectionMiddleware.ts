/**
 * SSRF protection Express middleware for Salesforce connector routes.
 *
 * Extracts the `targetUrl` field from the request body or query string,
 * validates it against the UrlAllowList, and rejects non-allowed URLs
 * with HTTP 403 before the route handler executes.
 *
 * Registration:
 *   import { createSsrfMiddleware, UrlAllowList } from '@opsera/shared';
 *   const ssrf = createSsrfMiddleware(new UrlAllowList());
 *   router.post('/proxy', ssrf, proxyHandler);
 *
 * API contract (WO-024):
 *   - Inspects: req.body.targetUrl or req.query.targetUrl (body takes precedence)
 *   - 403 response body: { error: 'SSRF_BLOCKED', message: string, correlationId: string }
 *   - 503 response body: { error: 'DNS_TIMEOUT', message: string, correlationId: string }
 *
 * Note: The WO specifies a Fastify preHandler plugin, but the established
 * codebase (WO-090) uses Express throughout. This module exports an Express
 * RequestHandler. The Fastify migration path is a one-line wrapper.
 */

import type { Request, Response, NextFunction, RequestHandler } from 'express';
import { createLogger } from '../../logging/logger.js';
import { getCorrelationId, generateCorrelationId } from '../../logging/correlation.js';
import { UrlAllowList, sanitiseUrlForLog } from '../../common/security/UrlAllowList.js';

const logger = createLogger('SsrfProtectionMiddleware');

export interface SsrfMiddlewareOptions {
  /** Pre-built UrlAllowList instance. If omitted, one is created from defaults/env. */
  allowList?: UrlAllowList;
}

/**
 * Factory that returns an Express RequestHandler implementing SSRF protection.
 * The middleware reads `targetUrl` from `req.body` or `req.query`, validates it,
 * and either calls `next()` (allowed) or sends a 403/503 response (blocked).
 */
export function createSsrfMiddleware(options?: SsrfMiddlewareOptions): RequestHandler {
  const allowList = options?.allowList ?? new UrlAllowList();

  return (req: Request, res: Response, next: NextFunction): void => {
    void (async () => {
      const correlationId = getCorrelationId() ?? generateCorrelationId();

      // Extract target URL — body takes precedence over query string
      const targetUrl = extractTargetUrl(req);

      if (targetUrl === undefined || targetUrl === '') {
        // No targetUrl present — pass through; the route handler decides if it's required
        next();
        return;
      }

      let result;
      try {
        result = await allowList.validate(targetUrl);
      } catch (err) {
        logger.error('SSRF middleware: unexpected validation error', err, {
          correlationId,
          sanitisedUrl: sanitiseUrlForLog(targetUrl),
        });
        res.status(503).json({
          error: 'SSRF_VALIDATION_ERROR',
          message: 'URL validation failed due to an internal error. Please retry.',
          correlationId,
        });
        return;
      }

      if (result.isAllowed) {
        next();
        return;
      }

      const isDnsTimeout = result.reason?.startsWith('DNS_TIMEOUT:') === true;

      // Log security event — query params and credentials are stripped from the URL
      const sanitised = sanitiseUrlForLog(targetUrl);
      logger.warn('SSRF_BLOCKED: outbound request rejected', {
        correlationId,
        sanitisedTargetUrl: sanitised,
        hostname: result.hostname,
        reason: result.reason,
        method: req.method,
        path: req.path,
      });

      if (isDnsTimeout) {
        res.status(503).set('Retry-After', '5').json({
          error: 'DNS_TIMEOUT',
          message: 'DNS resolution timed out — please retry shortly.',
          correlationId,
        });
        return;
      }

      res.status(403).json({
        error: 'SSRF_BLOCKED',
        message: `Request to the specified URL is not permitted: ${sanitised}`,
        correlationId,
      });
    })();
  };
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function extractTargetUrl(req: Request): string | undefined {
  // Body takes precedence (POST/PUT requests)
  if (typeof req.body === 'object' && req.body !== null) {
    const body = req.body as Record<string, unknown>;
    if (typeof body['targetUrl'] === 'string') {
      return body['targetUrl'];
    }
  }
  // Fallback to query string (GET requests)
  const q = req.query['targetUrl'];
  if (typeof q === 'string') return q;
  return undefined;
}
