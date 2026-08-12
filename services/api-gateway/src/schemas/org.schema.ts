import type { AjvSchema } from '@opsera/shared';

export const orgQuerySchema: AjvSchema = {
  type: 'object',
  properties: {
    page: { type: 'string', pattern: '^[0-9]+$' },
    pageSize: { type: 'string', pattern: '^[0-9]+$' },
  },
  additionalProperties: false,
};

export const orgCreateBodySchema: AjvSchema = {
  type: 'object',
  required: ['orgId', 'instanceUrl'],
  properties: {
    orgId: { type: 'string', minLength: 15, maxLength: 18, pattern: '^[a-zA-Z0-9]+$' },
    instanceUrl: { type: 'string', format: 'uri', maxLength: 255 },
    label: { type: 'string', maxLength: 255 },
  },
  additionalProperties: false,
};
