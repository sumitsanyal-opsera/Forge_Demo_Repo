/**
 * Prisma seed script for Opsera Stuck Pipeline Detection System.
 *
 * Creates comprehensive fixture data for all 11 tables:
 *   - 2 users, 2 Salesforce orgs, 3 monitored pipelines
 *   - threshold configs, execution baselines
 *   - 54 pipeline executions + steps across June/July/August 2026
 *   - detection events, alert records
 *   - alert recipients, audit log entries
 *
 * Run: npx prisma db seed  (from packages/shared directory)
 */

import { PrismaClient } from '@prisma/client';
import { seedExecutions } from './fixtures/execution-fixtures.js';
import {
  seedThresholdConfigs,
  seedBaselines,
  seedDetectionAndAlerts,
  seedAlertRecipients,
  seedAuditLog,
} from './fixtures/supporting-fixtures.js';

const prisma = new PrismaClient();

async function main(): Promise<void> {
  console.log('🌱 Starting seed...');

  // ── Users ────────────────────────────────────────────────────────────────────
  const adminUser = await prisma.user.upsert({
    where: { opseraUserId: 'opsera-user-admin-001' },
    update: {},
    create: {
      opseraUserId: 'opsera-user-admin-001',
      // Email is PII — marked for application-layer encryption in a future story
      email: 'admin@example.com',
      displayName: 'Admin User',
      role: 'ADMIN',
      isActive: true,
    },
  });

  const engineerUser = await prisma.user.upsert({
    where: { opseraUserId: 'opsera-user-eng-002' },
    update: {},
    create: {
      opseraUserId: 'opsera-user-eng-002',
      email: 'engineer@example.com',
      displayName: 'Release Engineer',
      role: 'RELEASE_ENGINEER',
      isActive: true,
    },
  });

  console.log(`  ✓ users: 2`);

  // ── Salesforce Orgs ───────────────────────────────────────────────────────────
  const org1 = await prisma.salesforceOrg.upsert({
    where: { orgId: '00D000000000001EAA' },
    update: {},
    create: {
      orgId: '00D000000000001EAA',
      orgName: 'Opsera Production Org',
      instanceUrl: 'https://opsera.my.salesforce.com',
      connectionStatus: 'CONNECTED',
      // tokenVaultReference: key into secrets vault — never raw OAuth token
      tokenVaultReference: 'vault://opsera/sf-org-prod/oauth-token',
      connectedBy: adminUser.id,
      connectedAt: new Date('2026-06-01T08:00:00Z'),
      lastHealthCheckAt: new Date('2026-08-12T00:00:00Z'),
    },
  });

  const org2 = await prisma.salesforceOrg.upsert({
    where: { orgId: '00D000000000002EAA' },
    update: {},
    create: {
      orgId: '00D000000000002EAA',
      orgName: 'Opsera Sandbox Org',
      instanceUrl: 'https://opsera--sandbox.sandbox.my.salesforce.com',
      connectionStatus: 'CONNECTED',
      tokenVaultReference: 'vault://opsera/sf-org-sandbox/oauth-token',
      connectedBy: engineerUser.id,
      connectedAt: new Date('2026-06-15T10:00:00Z'),
      lastHealthCheckAt: new Date('2026-08-12T00:00:00Z'),
    },
  });

  console.log(`  ✓ salesforce_orgs: 2`);

  // ── Monitored Pipelines ───────────────────────────────────────────────────────
  const pipeline1 = await prisma.monitoredPipeline.upsert({
    where: { opseraPipelineId: 'pipeline-apex-deploy-001' },
    update: {},
    create: {
      opseraPipelineId: 'pipeline-apex-deploy-001',
      pipelineName: 'Apex Classes Deploy',
      salesforceOrgId: org1.id,
      monitoringEnabled: true,
      createdBy: adminUser.id,
    },
  });

  const pipeline2 = await prisma.monitoredPipeline.upsert({
    where: { opseraPipelineId: 'pipeline-full-deploy-002' },
    update: {},
    create: {
      opseraPipelineId: 'pipeline-full-deploy-002',
      pipelineName: 'Full Metadata Deploy',
      salesforceOrgId: org1.id,
      monitoringEnabled: true,
      createdBy: engineerUser.id,
    },
  });

  const pipeline3 = await prisma.monitoredPipeline.upsert({
    where: { opseraPipelineId: 'pipeline-sandbox-sync-003' },
    update: {},
    create: {
      opseraPipelineId: 'pipeline-sandbox-sync-003',
      pipelineName: 'Sandbox Sync Pipeline',
      salesforceOrgId: org2.id,
      monitoringEnabled: true,
      createdBy: engineerUser.id,
    },
  });

  console.log(`  ✓ monitored_pipelines: 3`);

  const pipelineIds: [string, string, string] = [pipeline1.id, pipeline2.id, pipeline3.id];

  // ── Executions + Steps ────────────────────────────────────────────────────────
  const { executionCount, stepCount } = await seedExecutions(prisma, pipelineIds);
  console.log(`  ✓ pipeline_executions: ${executionCount}, execution_steps: ${stepCount}`);

  // ── Thresholds ────────────────────────────────────────────────────────────────
  const thresholdCount = await seedThresholdConfigs(prisma, pipelineIds, org1.id);
  console.log(`  ✓ threshold_configs: ${thresholdCount}`);

  // ── Baselines ─────────────────────────────────────────────────────────────────
  const baselineCount = await seedBaselines(prisma, pipelineIds);
  console.log(`  ✓ execution_baselines: ${baselineCount}`);

  // ── Detection Events + Alerts ─────────────────────────────────────────────────
  const { detectionCount, alertCount } = await seedDetectionAndAlerts(prisma, pipelineIds);
  console.log(`  ✓ detection_events: ${detectionCount}, alert_records: ${alertCount}`);

  // ── Alert Recipients ──────────────────────────────────────────────────────────
  const recipientCount = await seedAlertRecipients(prisma, pipelineIds, org1.id);
  console.log(`  ✓ alert_recipients: ${recipientCount}`);

  // ── Audit Log ─────────────────────────────────────────────────────────────────
  const auditCount = await seedAuditLog(prisma, [adminUser.id, engineerUser.id]);
  console.log(`  ✓ audit_log: ${auditCount}`);

  console.log('✅ Seed complete');
}

main()
  .catch((err: unknown) => {
    console.error('Seed failed:', err);
    process.exit(1);
  })
  .finally(() => {
    void prisma.$disconnect();
  });
