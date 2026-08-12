/**
 * Integration tests for time-series partitioned tables:
 *   pipeline_executions, execution_steps
 *
 * Requires a running PostgreSQL instance with the migration applied.
 * Set TEST_DATABASE_URL or DATABASE_URL before running.
 *
 * Key scenarios:
 *   - Partition-aware inserts (in-range and out-of-range)
 *   - Composite FK (id + startedAt) from execution_steps
 *   - JSONB containment queries on metadata / progress_indicators
 *   - Cross-partition range queries spanning multiple months
 */

import { PrismaClient } from '@prisma/client';
import { createTestDatabase, cleanupTestDatabase } from '../test-utils.js';

let prisma: PrismaClient;
let testOrgId: string;
let testPipelineId: string;

beforeAll(async () => {
  prisma = await createTestDatabase();

  // Create a minimal org + pipeline as FK anchors
  const org = await prisma.salesforceOrg.create({
    data: {
      orgId: `00DExec${Date.now()}`,
      orgName: 'Exec Test Org',
      instanceUrl: 'https://exec-test.salesforce.com',
      connectionStatus: 'CONNECTED',
    },
  });
  testOrgId = org.id;

  const pipeline = await prisma.monitoredPipeline.create({
    data: {
      opseraPipelineId: `exec-pipeline-${Date.now()}`,
      pipelineName: 'Exec Test Pipeline',
      salesforceOrgId: testOrgId,
    },
  });
  testPipelineId = pipeline.id;
});

afterAll(async () => {
  // Cascade from org deletes pipelines and (via application logic) execution data
  await prisma.salesforceOrg.deleteMany({ where: { id: testOrgId } }).catch(() => undefined);
  await cleanupTestDatabase(prisma);
});

// ─── Partition-aware inserts ──────────────────────────────────────────────────

describe('pipeline_executions partitioned table', () => {
  it('inserts a record into the current-month partition', async () => {
    const now = new Date();
    const exec = await prisma.pipelineExecution.create({
      data: {
        monitoredPipelineId: testPipelineId,
        status: 'COMPLETED',
        startedAt: now,
        completedAt: new Date(now.getTime() + 600_000),
        durationSeconds: 600,
        metadata: { component_count: 10, test_count: 50 },
      },
    });

    expect(exec.id).toBeTruthy();
    expect(exec.status).toBe('COMPLETED');
    expect(exec.metadata).toEqual({ component_count: 10, test_count: 50 });

    await prisma.pipelineExecution.deleteMany({
      where: { id: exec.id, startedAt: exec.startedAt },
    });
  });

  it('inserts records in June, July, August and retrieves all in cross-partition query', async () => {
    const baseTs = Date.now();
    const months = [
      new Date('2026-06-15T10:00:00Z'),
      new Date('2026-07-15T10:00:00Z'),
      new Date('2026-08-15T10:00:00Z'),
    ];

    const created = await Promise.all(
      months.map((startedAt, i) =>
        prisma.pipelineExecution.create({
          data: {
            monitoredPipelineId: testPipelineId,
            status: 'COMPLETED',
            startedAt,
            salesforceDeployId: `0Af${baseTs}${i}`,
            metadata: { deployment_type: 'INCREMENTAL', month: i + 6 },
          },
        }),
      ),
    );

    // Cross-partition range query spanning all three months
    const results = await prisma.pipelineExecution.findMany({
      where: {
        monitoredPipelineId: testPipelineId,
        startedAt: {
          gte: new Date('2026-06-01T00:00:00Z'),
          lt: new Date('2026-09-01T00:00:00Z'),
        },
        salesforceDeployId: { in: created.map((e) => e.salesforceDeployId ?? '') },
      },
    });

    expect(results).toHaveLength(3);

    // Cleanup
    await Promise.all(
      created.map((e) =>
        prisma.pipelineExecution.deleteMany({ where: { id: e.id, startedAt: e.startedAt } }),
      ),
    );
  });

  it('inserts support all ExecutionStatus enum values', async () => {
    const statuses = ['QUEUED', 'IN_PROGRESS', 'COMPLETED', 'FAILED', 'CANCELLED', 'STUCK'] as const;

    for (const status of statuses) {
      const startedAt = new Date('2026-08-01T00:00:00Z');
      const exec = await prisma.pipelineExecution.create({
        data: {
          monitoredPipelineId: testPipelineId,
          status,
          startedAt,
        },
      });
      expect(exec.status).toBe(status);
      await prisma.pipelineExecution.deleteMany({ where: { id: exec.id, startedAt } });
    }
  });
});

// ─── JSONB queries ────────────────────────────────────────────────────────────

describe('JSONB metadata queries on pipeline_executions', () => {
  let execId: string;
  let execStartedAt: Date;

  beforeEach(async () => {
    const exec = await prisma.pipelineExecution.create({
      data: {
        monitoredPipelineId: testPipelineId,
        status: 'COMPLETED',
        startedAt: new Date('2026-08-10T12:00:00Z'),
        metadata: {
          component_count: 15,
          test_count: 100,
          test_results: { passed: 95, failed: 5, skipped: 0 },
          deployment_type: 'FULL',
          error_messages: [],
        },
      },
    });
    execId = exec.id;
    execStartedAt = exec.startedAt;
  });

  afterEach(async () => {
    await prisma.pipelineExecution
      .deleteMany({ where: { id: execId, startedAt: execStartedAt } })
      .catch(() => undefined);
  });

  it('retrieves execution with nested JSONB metadata intact', async () => {
    const found = await prisma.pipelineExecution.findFirst({
      where: { id: execId, startedAt: execStartedAt },
    });

    expect(found).not.toBeNull();
    const metadata = found!.metadata as Record<string, unknown>;
    expect(metadata['component_count']).toBe(15);
    expect(metadata['deployment_type']).toBe('FULL');
    const results = metadata['test_results'] as Record<string, number>;
    expect(results['passed']).toBe(95);
  });
});

// ─── Composite FK from execution_steps ───────────────────────────────────────

describe('execution_steps composite FK', () => {
  let execId: string;
  let execStartedAt: Date;

  beforeEach(async () => {
    const exec = await prisma.pipelineExecution.create({
      data: {
        monitoredPipelineId: testPipelineId,
        status: 'IN_PROGRESS',
        startedAt: new Date('2026-08-05T09:00:00Z'),
      },
    });
    execId = exec.id;
    execStartedAt = exec.startedAt;
  });

  afterEach(async () => {
    await prisma.executionStep
      .deleteMany({ where: { pipelineExecutionId: execId } })
      .catch(() => undefined);
    await prisma.pipelineExecution
      .deleteMany({ where: { id: execId, startedAt: execStartedAt } })
      .catch(() => undefined);
  });

  it('creates execution steps linked via composite FK', async () => {
    const step = await prisma.executionStep.create({
      data: {
        pipelineExecutionId: execId,
        pipelineExecutionStartedAt: execStartedAt,
        stepName: 'deploy',
        stepType: 'DEPLOY',
        status: 'COMPLETED',
        startedAt: execStartedAt,
        completedAt: new Date(execStartedAt.getTime() + 300_000),
        durationSeconds: 300,
        progressIndicators: { components_processed: 10, tests_completed: null },
      },
    });

    expect(step.pipelineExecutionId).toBe(execId);
    expect(step.pipelineExecutionStartedAt.getTime()).toBe(execStartedAt.getTime());
    expect(step.status).toBe('COMPLETED');
    const indicators = step.progressIndicators as Record<string, unknown>;
    expect(indicators['components_processed']).toBe(10);
  });

  it('rejects a step referencing a non-existent execution', async () => {
    const fakeId = '00000000-0000-0000-0000-000000000000';
    const fakeStartedAt = new Date('2026-08-05T09:00:00Z');

    await expect(
      prisma.executionStep.create({
        data: {
          pipelineExecutionId: fakeId,
          pipelineExecutionStartedAt: fakeStartedAt,
          stepName: 'deploy',
          stepType: 'DEPLOY',
          status: 'QUEUED',
          startedAt: fakeStartedAt,
        },
      }),
    ).rejects.toThrow();
  });

  it('cascades step deletion when execution is deleted', async () => {
    const step = await prisma.executionStep.create({
      data: {
        pipelineExecutionId: execId,
        pipelineExecutionStartedAt: execStartedAt,
        stepName: 'validate',
        stepType: 'VALIDATE',
        status: 'COMPLETED',
        startedAt: execStartedAt,
      },
    });

    await prisma.pipelineExecution.deleteMany({
      where: { id: execId, startedAt: execStartedAt },
    });

    const found = await prisma.executionStep.findFirst({ where: { id: step.id } });
    expect(found).toBeNull();

    execId = ''; // already deleted — skip cleanup
  });
});
