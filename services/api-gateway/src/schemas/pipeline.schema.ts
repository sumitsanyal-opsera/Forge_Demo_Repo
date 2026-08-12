import type { AjvSchema } from '@opsera/shared';

export const pipelineQuerySchema: AjvSchema = {
  type: 'object',
  properties: {
    orgId: { type: 'string', minLength: 1, maxLength: 18, pattern: '^[a-zA-Z0-9]+$' },
    status: { type: 'string', enum: ['monitoring', 'at_risk', 'potentially_stuck', 'confirmed_stuck', 'resolved'] },
    page: { type: 'string', pattern: '^[0-9]+$' },
    pageSize: { type: 'string', pattern: '^[0-9]+$' },
  },
  additionalProperties: false,
};

export const pipelineDetectionBodySchema: AjvSchema = {
  type: 'object',
  required: ['pipelineId', 'orgId'],
  properties: {
    pipelineId: { type: 'string', minLength: 1, maxLength: 255 },
    orgId: { type: 'string', minLength: 1, maxLength: 18, pattern: '^[a-zA-Z0-9]+$' },
    deploymentId: { type: 'string', minLength: 1, maxLength: 255 },
    severity: { type: 'string', enum: ['warning', 'critical'] },
  },
  additionalProperties: false,
};
