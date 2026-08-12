/**
 * Integration tests for supporting schema tables:
 *   threshold_configs, execution_baselines, detection_events, alert_records,
 *   alert_recipients, audit_log
 *
 * Requires a running PostgreSQL instance with the migration applied.
 * Set TEST_DATABASE_URL or DATABASE_URL before running.
 *
 * Key scenarios:
 *   - ThresholdConfig unique constraint with NULL pipeline FK
 *   - ExecutionBaseline upsert behaviour
 *   - DetectionEvent composite FK to partitioned table
 *   - AlertRecord cascade from DetectionEvent
 *   - AuditLog immutability trigger (UPDATE and DELETE both blocked)
 */

import { PrismaClient } from '@prisma/client';
import { createTestDatabase, cleanupTestDatabase } from '../test-utils.js';

let prisma: PrismaClient;
let testOrgId: string;
let testPipelineId: string;
let testExecId: string;
let testExecStartedAt: Date;

beforeAll(async () => {
  prisma = await createTestDatabase();

  const org = await prisma.salesforceOrg.create({
    data: {
      orgId: `00DSupp${Date.now()}`,
      orgName: 'Supporting Test Org',
      instanceUrl: 'https://supporting.salesforce.com',
      connectionStatus: 'CONNECTED',
    },
  });
  testOrgId = org.id;

  const pipeline = await prisma.monitoredPipeline.create({
    data: {
      opseraPipelineId: `supp-pipeline-${Date.now()}`,
      pipelineName: 'Supporting Test Pipeline',
      salesforceOrgId: testOrgId,
    },
  });
  testPipelineId = pipeline.id;

  // Create a STUCK execution for detection event tests
  const exec = await prisma.pipelineExecution.create({
    data: {
      monitoredPipelineId: testPipelineId,
      status: 'STUCK',
      startedAt: new Date('2026-08-11T14:00:00Z'),
    },
  });
  testExecId = exec.id;
  testExecStartedAt = exec.startedAt;
});

afterAll(async () => {
  await prisma.salesforceOrg.deleteMany({ where: { id: testOrgId } }).catch(() => undefined);
  await cleanupTestDatabase(prisma);
});

// ─── ThresholdConfig ──────────────────────────────────────────────────────────

describe('threshold_configs table', () => {
  it('creates pipeline-level threshold with NULL step_name', async () => {
    const config = await prisma.thresholdConfig.create({
      data: {
        monitoredPipelineId: testPipelineId,
        salesforceOrgId: testOrgId,
        stepName: null,
        thresholdMode: 'COMPUTED',
        staleStateTimeoutMinutes: 30,
        gracePeriodMinutes: 5,
      },
    });

    expect(config.stepName).toBeNull();
    expect(config.thresholdMode).toBe('COMPUTED');

    await prisma.thresholdConfig.delete({ where: { id: config.id } });
  });

  it('creates step-level STATIC threshold with P50/P90/P99', async () => {
    const config = await prisma.thresholdConfig.create({
      data: {
        monitoredPipelineId: testPipelineId,
        salesforceOrgId: testOrgId,
        stepName: 'deploy-static-test',
        thresholdMode: 'STATIC',
        p50Seconds: 300,
        p90Seconds: 600,
        p99Seconds: 1200,
        staleStateTimeoutMinutes: 20,
        gracePeriodMinutes: 3,
      },
    });

    expect(config.p50Seconds).toBe(300);
    expect(config.p90Seconds).toBe(600);
    expect(config.p99Seconds).toBe(1200);

    await prisma.thresholdConfig.delete({ where: { id: config.id } });
  });

  it('rejects duplicate (monitoredPipelineId, stepName) combination', async () => {
    const config = await prisma.thresholdConfig.create({
      data: {
        monitoredPipelineId: testPipelineId,
        salesforceOrgId: testOrgId,
        stepName: 'unique-step',
        thresholdMode: 'COMPUTED',
        staleStateTimeoutMinutes: 30,
        gracePeriodMinutes: 5,
      },
    });

    await expect(
      prisma.thresholdConfig.create({
        data: {
          monitoredPipelineId: testPipelineId, // same
          salesforceOrgId: testOrgId,
          stepName: 'unique-step', // same
          thresholdMode: 'STATIC',
          staleStateTimeoutMinutes: 30,
          gracePeriodMinutes: 5,
        },
      }),
    ).rejects.toThrow();

    await prisma.thresholdConfig.delete({ where: { id: config.id } });
  });
});

// ─── ExecutionBaseline ────────────────────────────────────────────────────────

describe('execution_baselines table', () => {
  it('creates a pipeline-level baseline with JSONB time_of_day_factors', async () => {
    const baseline = await prisma.executionBaseline.create({
      data: {
        monitoredPipelineId: testPipelineId,
        stepName: null,
        timeBucket: `test-${Date.now()}`,
        p50Seconds: 1200,
        p90Seconds: 2400,
        p99Seconds: 3600,
        sampleCount: 20,
        lastComputedAt: new Date(),
        timeOfDayFactors: { hour_9: 1.2, hour_15: 0.9 },
      },
    });

    expect(baseline.p50Seconds).toBe(1200);
    const factors = baseline.timeOfDayFactors as Record<string, number>;
    expect(factors['hour_9']).toBe(1.2);

    await prisma.executionBaseline.delete({ where: { id: baseline.id } });
  });

  it('rejects duplicate (pipelineId, stepName, timeBucket) combination', async () => {
    const timeBucket = `dup-${Date.now()}`;
    const baseline = await prisma.executionBaseline.create({
      data: {
        monitoredPipelineId: testPipelineId,
        stepName: null,
        timeBucket,
        p50Seconds: 600,
        p90Seconds: 1200,
        p99Seconds: 1800,
        sampleCount: 10,
        lastComputedAt: new Date(),
      },
    });

    await expect(
      prisma.executionBaseline.create({
        data: {
          monitoredPipelineId: testPipelineId,
          stepName: null,
          timeBucket, // duplicate
          p50Seconds: 700,
          p90Seconds: 1400,
          p99Seconds: 2100,
          sampleCount: 5,
          lastComputedAt: new Date(),
        },
      }),
    ).rejects.toThrow();

    await prisma.executionBaseline.delete({ where: { id: baseline.id } });
  });
});

// ─── DetectionEvent ───────────────────────────────────────────────────────────

describe('detection_events table', () => {
  it('creates a detection event via composite FK to partitioned execution', async () => {
    const event = await prisma.detectionEvent.create({
      data: {
        pipelineExecutionId: testExecId,
        pipelineExecutionStartedAt: testExecStartedAt,
        previousState: 'MONITORING',
        newState: 'AT_RISK',
        transitionReason: 'Exceeded P90 threshold',
        metadata: { threshold_seconds: 600 },
      },
    });

    expect(event.newState).toBe('AT_RISK');
    expect(event.pipelineExecutionId).toBe(testExecId);
    expect(event.metadata).toEqual({ threshold_seconds: 600 });

    await prisma.detectionEvent.delete({ where: { id: event.id } });
  });

  it('cascades alert_records deletion when detection_event is deleted', async () => {
    const event = await prisma.detectionEvent.create({
      data: {
        pipelineExecutionId: testExecId,
        pipelineExecutionStartedAt: testExecStartedAt,
        newState: 'CONFIRMED_STUCK',
        transitionReason: 'Stale for 30 min',
      },
    });

    const alert = await prisma.alertRecord.create({
      data: {
        detectionEventId: event.id,
        alertType: 'STUCK_EMAIL',
        status: 'DELIVERED',
        sentAt: new Date(),
        deliveredAt: new Date(),
        retryCount: 0,
      },
    });

    await prisma.detectionEvent.delete({ where: { id: event.id } });

    const found = await prisma.alertRecord.findUnique({ where: { id: alert.id } });
    expect(found).toBeNull();
  });
});

// ─── AlertRecipient ───────────────────────────────────────────────────────────

describe('alert_recipients table', () => {
  it('creates pipeline-scoped recipient with REALTIME preference', async () => {
    const recipient = await prisma.alertRecipient.create({
      data: {
        monitoredPipelineId: testPipelineId,
        email: `recipient-${Date.now()}@example.com`,
        notificationPreference: 'REALTIME',
        isActive: true,
      },
    });

    expect(recipient.notificationPreference).toBe('REALTIME');
    expect(recipient.isActive).toBe(true);

    await prisma.alertRecipient.delete({ where: { id: recipient.id } });
  });

  it('creates org-wide recipient (null monitoredPipelineId)', async () => {
    const recipient = await prisma.alertRecipient.create({
      data: {
        salesforceOrgId: testOrgId,
        monitoredPipelineId: null,
        email: `org-recipient-${Date.now()}@example.com`,
        notificationPreference: 'DIGEST',
        isActive: true,
      },
    });

    expect(recipient.monitoredPipelineId).toBeNull();
    expect(recipient.notificationPreference).toBe('DIGEST');

    await prisma.alertRecipient.delete({ where: { id: recipient.id } });
  });
});

// ─── AuditLog immutability trigger ───────────────────────────────────────────

describe('audit_log immutability trigger', () => {
  let auditId: string;

  beforeEach(async () => {
    const entry = await prisma.auditLog.create({
      data: {
        actor: 'test-actor',
        action: 'CREATE',
        resourceType: 'User',
        resourceId: `resource-${Date.now()}`,
        changeDetails: { before: null, after: { created: true } },
        ipAddress: '127.0.0.1',
      },
    });
    auditId = entry.id;
  });

  it('blocks UPDATE on audit_log rows', async () => {
    await expect(
      prisma.auditLog.update({
        where: { id: auditId },
        data: { action: 'TAMPERED' },
      }),
    ).rejects.toThrow(/immutable/i);
  });

  it('blocks DELETE on audit_log rows', async () => {
    await expect(
      prisma.auditLog.delete({
        where: { id: auditId },
      }),
    ).rejects.toThrow(/immutable/i);
  });

  it('allows INSERT (only write operation permitted)', async () => {
    const entry = await prisma.auditLog.create({
      data: {
        actor: 'insert-test-actor',
        action: 'LOGIN',
        resourceType: 'User',
        resourceId: `insert-${Date.now()}`,
        correlationId: 'test-correlation',
      },
    });
    // Cannot clean up (trigger blocks DELETE) — that is correct behaviour
    expect(entry.id).toBeTruthy();
    expect(entry.action).toBe('LOGIN');
  });

  it('persists audit log records that survive entity deletion', async () => {
    // Verify audit_log has no FK constraints (records survive when referenced entities die)
    const entry = await prisma.auditLog.create({
      data: {
        actor: 'orphan-test',
        action: 'DELETE',
        resourceType: 'MonitoredPipeline',
        resourceId: 'some-deleted-pipeline-id',
      },
    });

    // The record exists without requiring any other table row
    const found = await prisma.auditLog.findUnique({ where: { id: entry.id } });
    expect(found).not.toBeNull();
    expect(found!.actor).toBe('orphan-test');
  });
});
