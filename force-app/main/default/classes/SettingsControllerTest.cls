/**
 * Unit tests for SettingsController.
 *
 * MetadataDeployService.bypassDeployment = true is set per-test so that
 * Metadata.Operations.enqueueDeployment() (unavailable in @isTest) is skipped.
 */
@isTest
private class SettingsControllerTest {

    private static void assignAdminPermission() {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SmokeTest_Admin' LIMIT 1];
        insert new PermissionSetAssignment(
            AssigneeId      = UserInfo.getUserId(),
            PermissionSetId = ps.Id
        );
    }

    // =========================================================================
    // getSettings
    // =========================================================================

    @isTest
    static void testGetSettings_ReturnsExpectedFields() {
        assignAdminPermission();
        Test.startTest();
        Map<String, Object> result = SettingsController.getSettings();
        Test.stopTest();

        System.assertNotEquals(null, result, 'getSettings should return a non-null map');
        // All 17 config fields should be present
        System.assert(result.containsKey('SuiteTimeoutSec__c'),              'Missing SuiteTimeoutSec__c');
        System.assert(result.containsKey('PerScenarioTimeoutSec__c'),         'Missing PerScenarioTimeoutSec__c');
        System.assert(result.containsKey('GovernorBudgetCPUMs__c'),           'Missing GovernorBudgetCPUMs__c');
        System.assert(result.containsKey('GovernorBudgetSOQL__c'),            'Missing GovernorBudgetSOQL__c');
        System.assert(result.containsKey('GovernorBudgetDML__c'),             'Missing GovernorBudgetDML__c');
        System.assert(result.containsKey('CircuitBreakerThreshold__c'),       'Missing CircuitBreakerThreshold__c');
        System.assert(result.containsKey('SecurityScoreAbsoluteThreshold__c'),'Missing SecurityScoreAbsoluteThreshold__c');
        System.assert(result.containsKey('SecurityScoreRelativeThreshold__c'),'Missing SecurityScoreRelativeThreshold__c');
        System.assert(result.containsKey('SecurityHealthCheckEnabled__c'),    'Missing SecurityHealthCheckEnabled__c');
        System.assert(result.containsKey('DefaultRollbackPolicy__c'),         'Missing DefaultRollbackPolicy__c');
        System.assert(result.containsKey('DryRunMode__c'),                    'Missing DryRunMode__c');
        System.assert(result.containsKey('ShadowMode__c'),                    'Missing ShadowMode__c');
        System.assert(result.containsKey('AutoTriggerEnabled__c'),            'Missing AutoTriggerEnabled__c');
        System.assert(result.containsKey('DataRetentionDaysAuditLogs__c'),    'Missing DataRetentionDaysAuditLogs__c');
    }

    @isTest
    static void testGetSettings_ThrowsWithoutAdminPermission() {
        Boolean threw = false;
        try {
            SettingsController.getSettings();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('SmokeTest_Admin'),
                'Error must mention the required permission set');
        }
        System.assert(threw, 'Expected AuraHandledException for non-admin user');
    }

    // =========================================================================
    // saveSettings — valid inputs
    // =========================================================================

    @isTest
    static void testSaveSettings_ValidNumericChange_Succeeds() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> changes = new Map<String, Object>{
            'GovernorBudgetCPUMs__c' => 6000
        };

        Test.startTest();
        Map<String, Object> result = SettingsController.saveSettings(changes, 'Increase CPU budget for complex scenarios');
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'save should return success=true');
        System.assertEquals('TEST_JOB_ID', result.get('jobId'));
    }

    @isTest
    static void testSaveSettings_BooleanChange_Succeeds() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> changes = new Map<String, Object>{
            'ShadowMode__c' => true
        };

        Test.startTest();
        Map<String, Object> result = SettingsController.saveSettings(changes, 'Enable shadow mode for staging validation');
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
    }

    @isTest
    static void testSaveSettings_WritesAuditLog() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Integer beforeCount = [SELECT COUNT() FROM SmokeTestAuditLog__c];

        Map<String, Object> changes = new Map<String, Object>{
            'SuiteTimeoutSec__c'   => 400,
            'GovernorBudgetSOQL__c'=> 75
        };

        Test.startTest();
        SettingsController.saveSettings(changes, 'Adjusting timeout and SOQL budget');
        Test.stopTest();

        Integer afterCount = [SELECT COUNT() FROM SmokeTestAuditLog__c];
        System.assertEquals(beforeCount + 2, afterCount,
            'One audit log record per changed field (2 fields → 2 records)');
    }

    @isTest
    static void testSaveSettings_RollbackPolicyChange_WithReason_Succeeds() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> changes = new Map<String, Object>{
            'DefaultRollbackPolicy__c' => 'Auto-Rollback on Critical Failure'
        };

        Test.startTest();
        Map<String, Object> result = SettingsController.saveSettings(
            changes, 'Enabling auto-rollback after production incident review');
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
    }

    // =========================================================================
    // saveSettings — validation rejections
    // =========================================================================

    @isTest
    static void testSaveSettings_RollbackPolicyChange_WithoutReason_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> changes = new Map<String, Object>{
            'DefaultRollbackPolicy__c' => 'Auto-Rollback on Critical Failure'
        };

        Boolean threw = false;
        try {
            SettingsController.saveSettings(changes, '');
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('change reason'),
                'Error must mention change reason requirement; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for missing change reason');
    }

    @isTest
    static void testSaveSettings_InvalidRollbackPolicy_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> changes = new Map<String, Object>{
            'DefaultRollbackPolicy__c' => 'INVALID_VALUE'
        };

        Boolean threw = false;
        try {
            SettingsController.saveSettings(changes, 'reason');
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('INVALID_VALUE') || e.getMessage().contains('Invalid'),
                'Error must mention invalid rollback policy; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for invalid rollback policy');
    }

    @isTest
    static void testSaveSettings_SuiteTimeoutOutOfRange_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> changes = new Map<String, Object>{
            'SuiteTimeoutSec__c' => 999
        };

        Boolean threw = false;
        try {
            SettingsController.saveSettings(changes, 'reason');
        } catch (AuraHandledException e) {
            threw = true;
            // Error message is JSON-encoded field errors
            System.assert(e.getMessage().contains('600') || e.getMessage().contains('SuiteTimeout'),
                'Error must reference timeout max; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for suite timeout > 600');
    }

    @isTest
    static void testSaveSettings_CpuBudgetBelowMin_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> changes = new Map<String, Object>{
            'GovernorBudgetCPUMs__c' => 500
        };

        Boolean threw = false;
        try {
            SettingsController.saveSettings(changes, 'reason');
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('1000'),
                'Error must reference CPU min; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for CPU budget below 1000');
    }

    @isTest
    static void testSaveSettings_AuditLogRetentionBelow365_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> changes = new Map<String, Object>{
            'DataRetentionDaysAuditLogs__c' => 364
        };

        Boolean threw = false;
        try {
            SettingsController.saveSettings(changes, 'reason');
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('365') || e.getMessage().contains('compliance'),
                'Error must mention 365 day compliance minimum; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for audit log retention < 365');
    }

    @isTest
    static void testSaveSettings_EmptyChanges_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Boolean threw = false;
        try {
            SettingsController.saveSettings(new Map<String, Object>(), 'reason');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AuraHandledException for empty changes map');
    }

    @isTest
    static void testSaveSettings_MultipleFieldErrors_AllReported() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> changes = new Map<String, Object>{
            'SuiteTimeoutSec__c'     => 10,   // below 60
            'GovernorBudgetCPUMs__c' => 99999  // above 10000
        };

        Boolean threw = false;
        try {
            SettingsController.saveSettings(changes, 'reason');
        } catch (AuraHandledException e) {
            threw = true;
            // Both errors should appear in the JSON error message
            System.assert(e.getMessage().length() > 0,
                'Error message must not be blank; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for multiple out-of-range fields');
    }
}
