import { type RequestHandler } from 'express';
import { createLogger, generateCorrelationId } from '@opsera/shared';

const logger = createLogger('waf');

interface WafRule {
  name: string;
  severity: 'CRITICAL' | 'HIGH' | 'MEDIUM';
  checkTargets: Array<'path' | 'query' | 'body' | 'headers'>;
  patterns: RegExp[];
}

// Paths that skip body content checks (Salesforce metadata payloads with Apex code)
const TRUSTED_PATHS_REGEX = /^\/api\/v1\/(pipelines|baselines)(\/|$)/;

const WAF_RULES: WafRule[] = [
  {
    name: 'SQL_INJECTION',
    severity: 'CRITICAL',
    checkTargets: ['path', 'query', 'headers'],
    patterns: [
      /(\bselect\b.+\bfrom\b)/i,
      /(\bunion\b.+\bselect\b)/i,
      /(;\s*drop\s+table)/i,
      /(;\s*delete\s+from)/i,
      /('(\s*or\s+)'?\d+'?\s*=\s*'?\d)/i,
      /(--\s*$)/,
      /(\bexec\s*\()/i,
      /(\bxp_cmdshell\b)/i,
    ],
  },
  {
    name: 'SQL_INJECTION_BODY',
    severity: 'CRITICAL',
    checkTargets: ['body'],
    patterns: [
      /(\bunion\b.+\bselect\b)/i,
      /(;\s*drop\s+table)/i,
      /(\bexec\s*\()/i,
      /(\bxp_cmdshell\b)/i,
    ],
  },
  {
    name: 'XSS',
    severity: 'HIGH',
    checkTargets: ['path', 'query', 'body', 'headers'],
    patterns: [
      /(<\s*script[^>]*>)/i,
      /(javascript\s*:)/i,
      /(on(error|load|click|mouse|focus|blur|submit)\s*=)/i,
      /(<\s*iframe[^>]*>)/i,
      /(document\.cookie)/i,
      /(document\.write\s*\()/i,
      /(eval\s*\()/i,
    ],
  },
  {
    name: 'PATH_TRAVERSAL',
    severity: 'HIGH',
    checkTargets: ['path', 'query'],
    patterns: [
      /\.\.\//,
      /\.\.\\/,
      /%2e%2e%2f/i,
      /%2e%2e\//i,
      /\.%2f/i,
      /\/etc\/passwd/,
      /\/etc\/shadow/,
      /c:\\windows/i,
    ],
  },
  {
    name: 'COMMAND_INJECTION',
    severity: 'CRITICAL',
    checkTargets: ['path', 'query', 'body'],
    patterns: [
      /(;\s*cat\s+\/)/i,
      /(;\s*ls\s+)/i,
      /(`[^`]+`)/,
      /(\$\([^)]+\))/,
      /(\|\s*nc\s+)/i,
      /(wget\s+http)/i,
      /(curl\s+http)/i,
    ],
  },
];

function extractStringTargets(req: Parameters<RequestHandler>[0], targets: WafRule['checkTargets'], isTrustedPath: boolean): string[] {
  const values: string[] = [];

  for (const target of targets) {
    if (target === 'path') {
      values.push(req.path);
    } else if (target === 'query') {
      values.push(req.url.split('?')[1] ?? '');
    } else if (target === 'headers') {
      const suspicious = ['user-agent', 'referer', 'x-forwarded-for'];
      for (const h of suspicious) {
        const val = req.headers[h];
        if (typeof val === 'string') values.push(val);
      }
    } else if (target === 'body' && !isTrustedPath) {
      const body = req.body as unknown;
      if (body !== undefined && body !== null) {
        values.push(JSON.stringify(body));
      }
    }
  }

  return values;
}

export interface WafOptions {
  enabled?: boolean;
}

/**
 * WAF middleware implementing OWASP CRS v4 pattern matching.
 * Returns 403 for blocked requests — never reveals which rule triggered.
 * Trusted paths skip body content checks to allow Salesforce Apex metadata.
 */
export function createWafMiddleware(options: WafOptions = {}): RequestHandler {
  const enabled = options.enabled ?? true;

  if (!enabled) {
    return (_req, _res, next) => next();
  }

  return (req, res, next) => {
    const correlationId = (req.headers['x-correlation-id'] as string | undefined) ?? generateCorrelationId();
    const isTrustedPath = TRUSTED_PATHS_REGEX.test(req.path);

    for (const rule of WAF_RULES) {
      const targets = extractStringTargets(req, rule.checkTargets, isTrustedPath);

      for (const value of targets) {
        for (const pattern of rule.patterns) {
          if (pattern.test(value)) {
            logger.warn('WAF blocked request', {
              rule: rule.name,
              severity: rule.severity,
              path: req.path,
              method: req.method,
              ip: req.ip,
              correlationId,
            });

            res.status(403).json({
              data: null,
              meta: {
                timestamp: new Date().toISOString(),
                requestId: correlationId,
              },
              errors: [
                {
                  code: 'WAF_BLOCKED',
                  message: 'Request blocked by security policy',
                },
              ],
            });
            return;
          }
        }
      }
    }

    next();
  };
}
