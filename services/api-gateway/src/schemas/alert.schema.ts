import type { AjvSchema } from '@opsera/shared';

export const alertCreateBodySchema: AjvSchema = {
  type: 'object',
  required: ['pipelineId', 'orgId', 'recipientIds'],
  properties: {
    pipelineId: { type: 'string', minLength: 1, maxLength: 255 },
    orgId: { type: 'string', minLength: 1, maxLength: 18, pattern: '^[a-zA-Z0-9]+$' },
    recipientIds: {
      type: 'array',
      items: { type: 'string', minLength: 1, maxLength: 255 },
      minItems: 1,
      maxItems: 50,
    },
    severity: { type: 'string', enum: ['warning', 'critical'] },
    message: { type: 'string', maxLength: 2000 },
  },
  additionalProperties: false,
};

export const alertQuerySchema: AjvSchema = {
  type: 'object',
  properties: {
    orgId: { type: 'string', minLength: 1, maxLength: 18, pattern: '^[a-zA-Z0-9]+$' },
    pipelineId: { type: 'string', minLength: 1, maxLength: 255 },
    status: { type: 'string', enum: ['sent', 'delivered', 'acknowledged', 'failed'] },
    page: { type: 'string', pattern: '^[0-9]+$' },
    pageSize: { type: 'string', pattern: '^[0-9]+$' },
  },
  additionalProperties: false,
};
