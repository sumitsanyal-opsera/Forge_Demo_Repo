import { type RequestHandler } from 'express';
import { generateCorrelationId } from '@opsera/shared';

const XML_MEDIA_TYPES = ['application/xml', 'text/xml', 'application/xhtml+xml'];

/**
 * Rejects XML request bodies with 415 Unsupported Media Type.
 * Prevents XXE (XML External Entity) injection attacks.
 */
export function createXmlRejectionMiddleware(): RequestHandler {
  return (req, res, next) => {
    const contentType = (req.headers['content-type'] ?? '').toLowerCase().split(';')[0]?.trim() ?? '';

    if (XML_MEDIA_TYPES.some((t) => contentType === t)) {
      res.status(415).json({
        data: null,
        meta: {
          timestamp: new Date().toISOString(),
          requestId: (req.headers['x-request-id'] as string | undefined) ?? generateCorrelationId(),
        },
        errors: [
          {
            code: 'UNSUPPORTED_MEDIA_TYPE',
            message: 'XML request bodies are not accepted. Use application/json.',
          },
        ],
      });
      return;
    }

    next();
  };
}
