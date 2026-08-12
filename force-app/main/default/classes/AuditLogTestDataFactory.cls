/**
 * Test fixture factory for AuditLogEntry instances.
 * Provides pre-populated entries for each of the five supported action types.
 * Reusable across AuditLogWriterTest and any downstream epic test class that
 * needs to create audit records in test setup.
 */
@isTest
public class AuditLogTestDataFactory {

    private static final String DEFAULT_RESOURCE_ID   = '001000000000001AAA';
    private static final String DEFAULT_RESOURCE_TYPE = 'SmokeTestExecution__c';
    private static final String DEFAULT_ACTOR_ID      = UserInfo.getUserId();

    public static AuditLogEntry createTestExecutionEntry() {
        return new AuditLogEntry.Builder()
            .actorUserId(DEFAULT_ACTOR_ID)
            .actionType(AuditLogEntry.ACTION_TEST_EXECUTION)
            .resourceId(DEFAULT_RESOURCE_ID)
            .resourceType(DEFAULT_RESOURCE_TYPE)
            .outcome('success')
            .ipAddress('10.0.0.1')
            .newValue('{"status":"completed","passed":10,"failed":0}')
            .build();
    }

    public static AuditLogEntry createConfigChangeEntry() {
        return new AuditLogEntry.Builder()
            .actorUserId(DEFAULT_ACTOR_ID)
            .actionType(AuditLogEntry.ACTION_CONFIG_CHANGE)
            .resourceId('SmokeTestConfig__mdt.Default')
            .resourceType('SmokeTestConfig__mdt')
            .oldValue('{"GovernorBudgetCPUMs__c":5000}')
            .newValue('{"GovernorBudgetCPUMs__c":7000}')
            .changeReason('Increased CPU budget for high-volume deployment window')
            .outcome('success')
            .build();
    }

    public static AuditLogEntry createRollbackEntry() {
        return new AuditLogEntry.Builder()
            .actorUserId(DEFAULT_ACTOR_ID)
            .actionType(AuditLogEntry.ACTION_ROLLBACK)
            .resourceId(DEFAULT_RESOURCE_ID)
            .resourceType(DEFAULT_RESOURCE_TYPE)
            .oldValue('{"status":"failed","securityScore":62}')
            .newValue('{"rollbackInitiated":true}')
            .outcome('success')
            .ipAddress('192.168.1.5')
            .build();
    }

    public static AuditLogEntry createAlertSentEntry() {
        return new AuditLogEntry.Builder()
            .actorUserId(DEFAULT_ACTOR_ID)
            .actionType(AuditLogEntry.ACTION_ALERT_SENT)
            .resourceId('SmokeTestAlertRoute__mdt.Admin_SecurityAlerts')
            .resourceType('SmokeTestAlertRoute__mdt')
            .newValue('{"channel":"email","recipient":"admin@example.com"}')
            .outcome('success')
            .build();
    }

    public static AuditLogEntry createDashboardAccessEntry() {
        return new AuditLogEntry.Builder()
            .actorUserId(DEFAULT_ACTOR_ID)
            .actionType(AuditLogEntry.ACTION_DASHBOARD_ACCESS)
            .resourceType('SmokeTestCenter')
            .outcome('success')
            .ipAddress('203.0.113.42')
            .build();
    }
}
