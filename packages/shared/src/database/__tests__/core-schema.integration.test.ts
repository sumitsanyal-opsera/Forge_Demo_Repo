/**
 * Integration tests for core relational schema tables:
 *   users, salesforce_orgs, monitored_pipelines
 *
 * Requires a running PostgreSQL instance.
 * Set TEST_DATABASE_URL or DATABASE_URL before running.
 *
 * Run: TEST_DATABASE_URL=postgresql://... npx jest core-schema.integration
 */

import { PrismaClient } from '@prisma/client';
import { createTestDatabase, cleanupTestDatabase } from '../test-utils.js';

let prisma: PrismaClient;

beforeAll(async () => {
  prisma = await createTestDatabase();
});

afterAll(async () => {
  await cleanupTestDatabase(prisma);
});

// ─── Users ────────────────────────────────────────────────────────────────────

describe('users table', () => {
  const uniqueUserId = `test-user-${Date.now()}`;
  let createdUserId: string;

  afterEach(async () => {
    if (createdUserId) {
      await prisma.user.deleteMany({ where: { id: createdUserId } }).catch(() => undefined);
    }
  });

  it('creates a user with all required fields', async () => {
    const user = await prisma.user.create({
      data: {
        opseraUserId: uniqueUserId,
        email: 'test@example.com',
        displayName: 'Test User',
        role: 'VIEWER',
        isActive: true,
      },
    });

    createdUserId = user.id;

    expect(user.id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
    );
    expect(user.opseraUserId).toBe(uniqueUserId);
    expect(user.role).toBe('VIEWER');
    expect(user.isActive).toBe(true);
    expect(user.createdAt).toBeInstanceOf(Date);
  });

  it('enforces unique opseraUserId constraint', async () => {
    const user = await prisma.user.create({
      data: {
        opseraUserId: uniqueUserId,
        email: 'test@example.com',
        displayName: 'Test User',
        role: 'VIEWER',
      },
    });
    createdUserId = user.id;

    await expect(
      prisma.user.create({
        data: {
          opseraUserId: uniqueUserId, // duplicate
          email: 'other@example.com',
          displayName: 'Other User',
          role: 'VIEWER',
        },
      }),
    ).rejects.toThrow();
  });

  it('supports all role enum values', async () => {
    const roles = ['ADMIN', 'RELEASE_ENGINEER', 'VIEWER'] as const;
    for (const role of roles) {
      const user = await prisma.user.create({
        data: {
          opseraUserId: `${uniqueUserId}-${role}`,
          email: `${role.toLowerCase()}@example.com`,
          displayName: role,
          role,
        },
      });
      expect(user.role).toBe(role);
      await prisma.user.delete({ where: { id: user.id } });
    }
  });
});

// ─── Salesforce Orgs ─────────────────────────────────────────────────────────

describe('salesforce_orgs table', () => {
  let userId: string;
  let orgId: string;

  beforeEach(async () => {
    const user = await prisma.user.create({
      data: {
        opseraUserId: `test-user-org-${Date.now()}`,
        email: 'org-test@example.com',
        displayName: 'Org Test User',
        role: 'ADMIN',
      },
    });
    userId = user.id;
  });

  afterEach(async () => {
    if (orgId) {
      await prisma.salesforceOrg.deleteMany({ where: { id: orgId } }).catch(() => undefined);
    }
    if (userId) {
      await prisma.user.deleteMany({ where: { id: userId } }).catch(() => undefined);
    }
  });

  it('creates a salesforce org with vault reference only', async () => {
    const org = await prisma.salesforceOrg.create({
      data: {
        orgId: `00D${Date.now()}AAA`,
        orgName: 'Test Org',
        instanceUrl: 'https://test.salesforce.com',
        connectionStatus: 'CONNECTED',
        // tokenVaultReference must be a vault key — never raw token
        tokenVaultReference: 'vault://test/sf/oauth',
        connectedBy: userId,
        connectedAt: new Date(),
      },
    });
    orgId = org.id;

    expect(org.connectionStatus).toBe('CONNECTED');
    expect(org.tokenVaultReference).toBe('vault://test/sf/oauth');
    expect(org.connectedBy).toBe(userId);
  });

  it('enforces ON DELETE RESTRICT for user reference', async () => {
    const org = await prisma.salesforceOrg.create({
      data: {
        orgId: `00D${Date.now()}BBB`,
        orgName: 'Restrict Test Org',
        instanceUrl: 'https://restrict-test.salesforce.com',
        connectionStatus: 'CONNECTED',
        connectedBy: userId,
        connectedAt: new Date(),
      },
    });
    orgId = org.id;

    // Deleting the user while org references them must fail
    await expect(prisma.user.delete({ where: { id: userId } })).rejects.toThrow();
  });

  it('supports all connection_status enum values', async () => {
    const statuses = ['CONNECTED', 'DISCONNECTED', 'ERROR'] as const;
    for (const status of statuses) {
      const org = await prisma.salesforceOrg.create({
        data: {
          orgId: `00D${Date.now()}${status.charAt(0)}`,
          orgName: `Status ${status}`,
          instanceUrl: `https://${status.toLowerCase()}.salesforce.com`,
          connectionStatus: status,
        },
      });
      expect(org.connectionStatus).toBe(status);
      await prisma.salesforceOrg.delete({ where: { id: org.id } });
    }
  });
});

// ─── Monitored Pipelines ──────────────────────────────────────────────────────

describe('monitored_pipelines table', () => {
  let userId: string;
  let sfOrgId: string;
  const createdPipelineIds: string[] = [];

  beforeEach(async () => {
    const user = await prisma.user.create({
      data: {
        opseraUserId: `test-user-pipe-${Date.now()}`,
        email: 'pipe-test@example.com',
        displayName: 'Pipeline Test User',
        role: 'RELEASE_ENGINEER',
      },
    });
    userId = user.id;

    const org = await prisma.salesforceOrg.create({
      data: {
        orgId: `00D${Date.now()}PPP`,
        orgName: 'Pipeline Test Org',
        instanceUrl: 'https://pipeline-test.salesforce.com',
        connectionStatus: 'CONNECTED',
      },
    });
    sfOrgId = org.id;
  });

  afterEach(async () => {
    await prisma.monitoredPipeline
      .deleteMany({ where: { id: { in: createdPipelineIds } } })
      .catch(() => undefined);
    createdPipelineIds.length = 0;
    if (sfOrgId) {
      await prisma.salesforceOrg.deleteMany({ where: { id: sfOrgId } }).catch(() => undefined);
    }
    if (userId) {
      await prisma.user.deleteMany({ where: { id: userId } }).catch(() => undefined);
    }
  });

  it('creates a monitored pipeline linked to an org', async () => {
    const pipeline = await prisma.monitoredPipeline.create({
      data: {
        opseraPipelineId: `pipeline-${Date.now()}`,
        pipelineName: 'Test Pipeline',
        salesforceOrgId: sfOrgId,
        monitoringEnabled: true,
        createdBy: userId,
      },
    });
    createdPipelineIds.push(pipeline.id);

    expect(pipeline.salesforceOrgId).toBe(sfOrgId);
    expect(pipeline.monitoringEnabled).toBe(true);
  });

  it('enforces unique opseraPipelineId constraint', async () => {
    const sharedId = `pipeline-unique-${Date.now()}`;

    const pipeline = await prisma.monitoredPipeline.create({
      data: {
        opseraPipelineId: sharedId,
        pipelineName: 'Pipeline A',
        salesforceOrgId: sfOrgId,
      },
    });
    createdPipelineIds.push(pipeline.id);

    await expect(
      prisma.monitoredPipeline.create({
        data: {
          opseraPipelineId: sharedId, // duplicate
          pipelineName: 'Pipeline B',
          salesforceOrgId: sfOrgId,
        },
      }),
    ).rejects.toThrow();
  });

  it('cascades delete from org to pipelines', async () => {
    // Create an org that we'll delete
    const tmpOrg = await prisma.salesforceOrg.create({
      data: {
        orgId: `00D${Date.now()}CCC`,
        orgName: 'Cascade Org',
        instanceUrl: 'https://cascade.salesforce.com',
        connectionStatus: 'CONNECTED',
      },
    });

    const pipeline = await prisma.monitoredPipeline.create({
      data: {
        opseraPipelineId: `pipeline-cascade-${Date.now()}`,
        pipelineName: 'Cascade Pipeline',
        salesforceOrgId: tmpOrg.id,
      },
    });

    await prisma.salesforceOrg.delete({ where: { id: tmpOrg.id } });

    // Pipeline should have been cascade deleted
    const found = await prisma.monitoredPipeline.findUnique({ where: { id: pipeline.id } });
    expect(found).toBeNull();
  });
});
