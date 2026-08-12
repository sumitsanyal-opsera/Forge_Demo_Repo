/**
 * Fixture data for supporting tables:
 * ThresholdConfig, ExecutionBaseline, DetectionEvent, AlertRecord, AlertRecipient, AuditLog.
 *
 * Called from seed.ts after core relational data and executions are inserted.
 */

import type { PrismaClient } from '@prisma/client';

export async function seedThresholdConfigs(
  prisma: PrismaClient,
  pipelineIds: string[],
  orgId: string,
): Promise<number> {
  let count = 0;

  for (const pipelineId of pipelineIds) {
    // Pipeline-level threshold (no specific step)
    await prisma.thresholdConfig.create({
      data: {
        monitoredPipelineId: pipelineId,
        salesforceOrgId: orgId,
        stepName: null,
        thresholdMode: 'COMPUTED',
        staleStateTimeoutMinutes: 30,
        gracePeriodMinutes: 5,
        peakHourMultiplier: 1.5,
      },
    });
    count++;

    // Step-level thresholds for deploy and test steps
    for (const stepName of ['deploy', 'test']) {
      await prisma.thresholdConfig.create({
        data: {
          monitoredPipelineId: pipelineId,
          salesforceOrgId: orgId,
          stepName,
          thresholdMode: 'STATIC',
          p50Seconds: stepName === 'deploy' ? 300 : 180,
          p90Seconds: stepName === 'deploy' ? 600 : 360,
          p99Seconds: stepName === 'deploy' ? 1200 : 720,
          staleStateTimeoutMinutes: 20,
          gracePeriodMinutes: 3,
          peakHourMultiplier: 1.3,
        },
      });
      count++;
    }
  }

  return count;
}

export async function seedBaselines(
  prisma: PrismaClient,
  pipelineIds: string[],
): Promise<number> {
  let count = 0;
  const timeBuckets = ['2026-06', '2026-07', '2026-08'];

  for (const pipelineId of pipelineIds) {
    for (const timeBucket of timeBuckets) {
      await prisma.executionBaseline.create({
        data: {
          monitoredPipelineId: pipelineId,
          stepName: null,
          timeBucket,
          p50Seconds: 1200 + Math.floor(Math.random() * 600),
          p90Seconds: 2400 + Math.floor(Math.random() * 600),
          p99Seconds: 3600 + Math.floor(Math.random() * 600),
          sampleCount: 15 + Math.floor(Math.random() * 10),
          lastComputedAt: new Date(`${timeBucket}-28T00:00:00Z`),
          timeOfDayFactors: {
            hour_6: 0.9,
            hour_9: 1.2,
            hour_12: 1.0,
            hour_15: 1.3,
            hour_18: 0.8,
          },
        },
      });
      count++;
    }
  }

  return count;
}

export async function seedDetectionAndAlerts(
  prisma: PrismaClient,
  pipelineIds: string[],
): Promise<{ detectionCount: number; alertCount: number }> {
  let detectionCount = 0;
  let alertCount = 0;

  // Find STUCK executions to generate detection events for
  const stuckExecutions = await prisma.pipelineExecution.findMany({
    where: { status: 'STUCK' },
    take: 6,
  });

  for (const exec of stuckExecutions) {
    // AT_RISK transition
    const atRiskEvent = await prisma.detectionEvent.create({
      data: {
        pipelineExecutionId: exec.id,
        pipelineExecutionStartedAt: exec.startedAt,
        previousState: 'MONITORING',
        newState: 'AT_RISK',
        transitionReason: 'Execution duration exceeded P90 threshold',
        detectedAt: new Date(exec.startedAt.getTime() + 600_000),
        metadata: { threshold_seconds: 600, actual_seconds: 650 },
      },
    });
    detectionCount++;

    // CONFIRMED_STUCK transition
    const stuckEvent = await prisma.detectionEvent.create({
      data: {
        pipelineExecutionId: exec.id,
        pipelineExecutionStartedAt: exec.startedAt,
        previousState: 'AT_RISK',
        newState: 'CONFIRMED_STUCK',
        transitionReason: 'No progress for 30 minutes — deploy step stalled',
        detectedAt: new Date(exec.startedAt.getTime() + 2_400_000),
        metadata: { stale_duration_minutes: 30, stuck_step: 'deploy' },
      },
    });
    detectionCount++;

    // Alert record for the stuck event
    await prisma.alertRecord.create({
      data: {
        detectionEventId: stuckEvent.id,
        alertType: 'STUCK_PIPELINE_EMAIL',
        status: 'DELIVERED',
        sentAt: new Date(stuckEvent.detectedAt.getTime() + 5_000),
        deliveredAt: new Date(stuckEvent.detectedAt.getTime() + 8_000),
        retryCount: 0,
      },
    });
    alertCount++;

    // Also create an alert for AT_RISK (sent but not delivered — simulating partial failure)
    await prisma.alertRecord.create({
      data: {
        detectionEventId: atRiskEvent.id,
        alertType: 'AT_RISK_NOTIFICATION',
        status: 'SENT',
        sentAt: new Date(atRiskEvent.detectedAt.getTime() + 3_000),
        retryCount: 1,
      },
    });
    alertCount++;
  }

  return { detectionCount, alertCount };
}

export async function seedAlertRecipients(
  prisma: PrismaClient,
  pipelineIds: string[],
  orgId: string,
): Promise<number> {
  let count = 0;

  // Org-wide recipient
  await prisma.alertRecipient.create({
    data: {
      salesforceOrgId: orgId,
      email: 'devops-team@example.com',
      notificationPreference: 'REALTIME',
      isActive: true,
    },
  });
  count++;

  // Pipeline-specific recipients
  for (let i = 0; i < Math.min(pipelineIds.length, 2); i++) {
    const pipelineId = pipelineIds[i];
    if (pipelineId == null) continue;
    await prisma.alertRecipient.create({
      data: {
        monitoredPipelineId: pipelineId,
        email: `pipeline-owner-${i + 1}@example.com`,
        notificationPreference: i === 0 ? 'REALTIME' : 'DIGEST',
        isActive: true,
      },
    });
    count++;
  }

  return count;
}

export async function seedAuditLog(prisma: PrismaClient, userIds: string[]): Promise<number> {
  const actions = [
    { action: 'CREATE', resourceType: 'SalesforceOrg' },
    { action: 'UPDATE', resourceType: 'MonitoredPipeline' },
    { action: 'CREATE', resourceType: 'ThresholdConfig' },
    { action: 'LOGIN', resourceType: 'User' },
  ];

  let count = 0;

  for (let i = 0; i < actions.length; i++) {
    const entry = actions[i];
    const actorId = userIds[i % userIds.length] ?? 'system';
    if (entry == null) continue;

    await prisma.auditLog.create({
      data: {
        actor: actorId,
        action: entry.action,
        resourceType: entry.resourceType,
        resourceId: `fixture-resource-${i + 1}`,
        changeDetails: {
          before: null,
          after: { created: true, index: i },
        },
        ipAddress: '10.0.0.1',
        correlationId: `seed-correlation-${i + 1}`,
      },
    });
    count++;
  }

  return count;
}
