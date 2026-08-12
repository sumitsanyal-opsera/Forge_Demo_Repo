/**
 * Generates 50+ PipelineExecution and ExecutionStep fixture records
 * spanning 3 months (2026-06, 2026-07, 2026-08) for realistic seed data.
 *
 * Records must fall within the partitioned table ranges defined in the migration SQL.
 * Run via: npx prisma db seed (configured in packages/shared/package.json)
 */

import type { PrismaClient } from '@prisma/client';

interface ExecutionRecord {
  monitoredPipelineId: string;
  status: 'QUEUED' | 'IN_PROGRESS' | 'COMPLETED' | 'FAILED' | 'CANCELLED' | 'STUCK';
  startedAt: Date;
  completedAt: Date | null;
  durationSeconds: number | null;
  salesforceDeployId: string;
  metadata: Record<string, unknown>;
}

function randomDuration(minSeconds: number, maxSeconds: number): number {
  return Math.floor(minSeconds + Math.random() * (maxSeconds - minSeconds));
}

function addSeconds(date: Date, seconds: number): Date {
  return new Date(date.getTime() + seconds * 1000);
}

/**
 * Builds 50+ execution records distributed across June, July, and August 2026.
 * Distribution: ~17 records per month, 3 pipelines × ~5-6 per pipeline per month.
 */
export function buildExecutionFixtures(pipelineIds: [string, string, string]): ExecutionRecord[] {
  const records: ExecutionRecord[] = [];

  const months = [
    { year: 2026, month: 6 },  // June
    { year: 2026, month: 7 },  // July
    { year: 2026, month: 8 },  // August
  ];

  const statuses: Array<'COMPLETED' | 'FAILED' | 'STUCK'> = ['COMPLETED', 'COMPLETED', 'COMPLETED', 'COMPLETED', 'FAILED', 'STUCK'];

  let deployCounter = 1000;

  for (const { year, month } of months) {
    for (const pipelineId of pipelineIds) {
      // 6 executions per pipeline per month = 54 total records
      for (let week = 0; week < 6; week++) {
        const day = (week * 4 + 1) % 28 + 1; // spread across the month
        const hour = 8 + (week % 10); // business hours
        const startedAt = new Date(Date.UTC(year, month - 1, day, hour, 0, 0));
        const status = statuses[week % statuses.length] ?? 'COMPLETED';
        const durationSeconds = status === 'COMPLETED'
          ? randomDuration(600, 3600)
          : status === 'FAILED'
            ? randomDuration(120, 900)
            : null; // STUCK — no completion

        const completedAt = durationSeconds != null
          ? addSeconds(startedAt, durationSeconds)
          : null;

        deployCounter++;

        records.push({
          monitoredPipelineId: pipelineId,
          status,
          startedAt,
          completedAt,
          durationSeconds,
          salesforceDeployId: `0Af${deployCounter.toString().padStart(12, '0')}`,
          metadata: {
            component_count: 5 + (deployCounter % 20),
            test_count: 50 + (deployCounter % 100),
            test_results: {
              passed: 45 + (deployCounter % 50),
              failed: status === 'FAILED' ? 5 + (deployCounter % 10) : 0,
              skipped: deployCounter % 5,
            },
            error_messages: status === 'FAILED'
              ? ['Deploy failed: ApexClass validation error in TestClass.cls line 42']
              : [],
            deployment_type: deployCounter % 3 === 0 ? 'FULL' : 'INCREMENTAL',
          },
        });
      }
    }
  }

  return records;
}

/**
 * Builds ExecutionStep fixture records for a given execution.
 * Generates 3-5 steps per execution mirroring a typical Salesforce deployment flow.
 */
export function buildStepFixtures(
  pipelineExecutionId: string,
  pipelineExecutionStartedAt: Date,
  executionStatus: string,
): Array<{
  pipelineExecutionId: string;
  pipelineExecutionStartedAt: Date;
  stepName: string;
  stepType: string;
  status: 'QUEUED' | 'IN_PROGRESS' | 'COMPLETED' | 'FAILED' | 'SKIPPED';
  startedAt: Date;
  completedAt: Date | null;
  durationSeconds: number | null;
  progressIndicators: Record<string, unknown>;
}> {
  const stepDefinitions = [
    { name: 'retrieve', type: 'RETRIEVE', baseDuration: 60 },
    { name: 'validate', type: 'VALIDATE', baseDuration: 120 },
    { name: 'deploy', type: 'DEPLOY', baseDuration: 300 },
    { name: 'test', type: 'RUN_TESTS', baseDuration: 180 },
    { name: 'verify', type: 'VERIFY', baseDuration: 30 },
  ];

  const steps = [];
  let currentTime = new Date(pipelineExecutionStartedAt.getTime());
  const isFailed = executionStatus === 'FAILED';
  const isStuck = executionStatus === 'STUCK';

  for (let i = 0; i < stepDefinitions.length; i++) {
    const def = stepDefinitions[i];
    if (def == null) continue;

    const isLastStep = i === stepDefinitions.length - 1;
    const isFailStep = isFailed && i === 2; // deploy step fails
    const isStuckStep = isStuck && i === 2; // deploy step stalls

    let stepStatus: 'COMPLETED' | 'FAILED' | 'IN_PROGRESS' | 'SKIPPED';
    if (isFailStep) stepStatus = 'FAILED';
    else if (isStuckStep) stepStatus = 'IN_PROGRESS'; // still running
    else if (isFailed && i > 2) stepStatus = 'SKIPPED'; // skipped after fail
    else stepStatus = 'COMPLETED';

    const duration = isStuckStep ? null : def.baseDuration + Math.floor(Math.random() * 60);
    const startedAt = new Date(currentTime.getTime());
    const completedAt = duration != null ? addSeconds(startedAt, duration) : null;

    steps.push({
      pipelineExecutionId,
      pipelineExecutionStartedAt,
      stepName: def.name,
      stepType: def.type,
      status: stepStatus,
      startedAt,
      completedAt,
      durationSeconds: duration,
      progressIndicators: {
        components_processed: isStuckStep ? 3 : (i + 1) * 10,
        tests_completed: def.type === 'RUN_TESTS' ? 45 : null,
        last_status_change_at: startedAt.toISOString(),
      },
    });

    if (completedAt != null) {
      currentTime = completedAt;
    }

    if (isFailStep || isStuckStep) break;
    if (isLastStep) break;
  }

  return steps;
}

/**
 * Seeds all execution and step fixture records into the database.
 * Called from seed.ts after core relational data is inserted.
 */
export async function seedExecutions(
  prisma: PrismaClient,
  pipelineIds: [string, string, string],
): Promise<{ executionCount: number; stepCount: number }> {
  const executions = buildExecutionFixtures(pipelineIds);
  let stepCount = 0;

  for (const exec of executions) {
    const created = await prisma.pipelineExecution.create({
      data: {
        monitoredPipelineId: exec.monitoredPipelineId,
        salesforceDeployId: exec.salesforceDeployId,
        status: exec.status,
        startedAt: exec.startedAt,
        completedAt: exec.completedAt,
        durationSeconds: exec.durationSeconds,
        metadata: exec.metadata,
      },
    });

    const steps = buildStepFixtures(created.id, created.startedAt, exec.status);
    for (const step of steps) {
      await prisma.executionStep.create({ data: step });
      stepCount++;
    }
  }

  return { executionCount: executions.length, stepCount };
}
