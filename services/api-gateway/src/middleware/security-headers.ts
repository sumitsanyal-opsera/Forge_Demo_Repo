import { randomBytes } from 'node:crypto';
import { type RequestHandler } from 'express';

export interface SecurityHeadersOptions {
  hstsMaxAge?: number;
  cspAdditionalSrc?: string[];
}

/**
 * Injects all required security headers on every response.
 * Generates a per-request CSP nonce stored on res.locals.cspNonce.
 * Removes the X-Powered-By header to reduce information leakage.
 */
export function createSecurityHeadersMiddleware(
  options: SecurityHeadersOptions = {},
): RequestHandler {
  const hstsMaxAge = options.hstsMaxAge ?? 31536000;

  return (_req, res, next) => {
    const nonce = randomBytes(16).toString('base64');
    (res.locals as Record<string, unknown>)['cspNonce'] = nonce;

    const additionalScriptSrc = (options.cspAdditionalSrc ?? []).join(' ');
    const scriptSrc = `'self' 'nonce-${nonce}'${additionalScriptSrc ? ` ${additionalScriptSrc}` : ''}`;

    res.setHeader(
      'Content-Security-Policy',
      [
        `default-src 'self'`,
        `script-src ${scriptSrc}`,
        `style-src 'self' 'unsafe-inline'`,
        `img-src 'self' data:`,
        `connect-src 'self'`,
        `font-src 'self'`,
        `object-src 'none'`,
        `frame-ancestors 'none'`,
        `base-uri 'self'`,
        `form-action 'self'`,
      ].join('; '),
    );

    res.setHeader(
      'Strict-Transport-Security',
      `max-age=${hstsMaxAge}; includeSubDomains`,
    );

    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
    res.removeHeader('X-Powered-By');

    next();
  };
}
