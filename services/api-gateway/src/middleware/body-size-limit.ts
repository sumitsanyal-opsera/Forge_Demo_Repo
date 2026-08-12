import { type RequestHandler } from 'express';
import { generateCorrelationId } from '@opsera/shared';

/**
 * Rejects requests with a Content-Length header exceeding the limit BEFORE
 * body parsing occurs, returning 413 with the standard error envelope.
 * Also relies on express.json/urlencoded limit options as a second defence.
 */
export function createBodySizeLimitMiddleware(limitBytes: number): RequestHandler {
  return (req, res, next) => {
    const contentLength = req.headers['content-length'];
    if (contentLength !== undefined) {
      const length = parseInt(contentLength, 10);
      if (!isNaN(length) && length > limitBytes) {
        res.status(413).json({
          data: null,
          meta: {
            timestamp: new Date().toISOString(),
            requestId: (req.headers['x-request-id'] as string | undefined) ?? generateCorrelationId(),
          },
          errors: [
            {
              code: 'PAYLOAD_TOO_LARGE',
              message: `Request body exceeds the maximum allowed size of ${limitBytes} bytes`,
            },
          ],
        });
        return;
      }
    }
    next();
  };
}
