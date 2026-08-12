import { type RequestHandler } from 'express';

const ALLOWED_METHODS = 'GET, POST, PUT, PATCH, DELETE, OPTIONS';
const ALLOWED_HEADERS = 'Authorization, Content-Type, X-Request-ID, X-Correlation-ID';
const MAX_AGE_SECONDS = '600';

/**
 * CORS middleware restricted to a single allowlisted origin.
 * Requests from any other origin receive no ACAO header (effectively blocked).
 * OPTIONS preflight requests are resolved before auth middleware runs.
 */
export function createCorsMiddleware(allowedOrigin: string): RequestHandler {
  return (req, res, next) => {
    const requestOrigin = req.headers['origin'];

    if (requestOrigin === allowedOrigin) {
      res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
      res.setHeader('Access-Control-Allow-Methods', ALLOWED_METHODS);
      res.setHeader('Access-Control-Allow-Headers', ALLOWED_HEADERS);
      res.setHeader('Access-Control-Max-Age', MAX_AGE_SECONDS);
      res.setHeader('Vary', 'Origin');
    }

    // Handle preflight before auth checks
    if (req.method === 'OPTIONS') {
      res.status(204).end();
      return;
    }

    next();
  };
}
