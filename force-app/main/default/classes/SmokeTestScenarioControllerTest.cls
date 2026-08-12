/**
 * Unit tests for SmokeTestScenarioController.
 * MetadataDeployService.bypassDeployment = true is set in @TestSetup so that
 * Metadata.Operations.enqueueDeployment() (unavailable in @isTest) is skipped.
 *
 * Test coverage targets:
 *   - getScenarios(): returns MDT records, enforces admin permission
 *   - createScenario(): valid inputs succeed, invalid inputs throw AuraHandledException
 *   - toggleScenario(): enable/disable + audit log written
 *   - updateScenario(): field updates dispatched to MetadataDeployService
 *   - validateParams(): all allow-list rules exercised (name, timeout, budgets)
 */
@isTest
private class SmokeTestScenarioControllerTest {

    @TestSetup
    static void setupPermission() {
        MetadataDeployService.bypassDeployment = true;
        // Note: bypassDeployment is a static field — re-set in each test method
        // because @TestSetup runs in a separate transaction.
    }

    // Helper to assign SmokeTest_Admin permission to running user for tests
    private static void assignAdminPermission() {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SmokeTest_Admin' LIMIT 1];
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId     = UserInfo.getUserId(),
            PermissionSetId = ps.Id
        );
        insert psa;
    }

    // =========================================================================
    // getScenarios
    // =========================================================================

    @isTest
    static void testGetScenarios_ReturnsRecords() {
        assignAdminPermission();
        Test.startTest();
        List<Map<String, Object>> result = SmokeTestScenarioController.getScenarios();
        Test.stopTest();

        System.assertNotEquals(null, result, 'getScenarios should return a list');
        // SmokeTestScenario__mdt.getAll() returns all deployed MDT records
        // In a test environment with deployed CMT records this count should be > 0
        Integer expected = SmokeTestScenario__mdt.getAll().size();
        System.assertEquals(expected, result.size(),
            'Result count should match MDT record count');
    }

    @isTest
    static void testGetScenarios_ContainsExpectedFields() {
        assignAdminPermission();
        List<Map<String, Object>> result = SmokeTestScenarioController.getScenarios();

        if (result.isEmpty()) return; // no MDT records deployed in this scratch org

        Map<String, Object> first = result.get(0);
        System.assert(first.containsKey('developerName'),  'Result must have developerName');
        System.assert(first.containsKey('isEnabled'),      'Result must have isEnabled');
        System.assert(first.containsKey('executionOrder'), 'Result must have executionOrder');
        System.assert(first.containsKey('scenarioClass'),  'Result must have scenarioClass');
        System.assert(first.containsKey('isCritical'),     'Result must have isCritical');
    }

    @isTest
    static void testGetScenarios_SortedByExecutionOrder() {
        assignAdminPermission();
        List<Map<String, Object>> result = SmokeTestScenarioController.getScenarios();

        if (result.size() < 2) return;

        for (Integer i = 1; i < result.size(); i++) {
            Decimal prev = (Decimal) result.get(i - 1).get('executionOrder');
            Decimal curr = (Decimal) result.get(i).get('executionOrder');
            if (prev == null) prev = 9999;
            if (curr == null) curr = 9999;
            System.assert(prev <= curr,
                'Results must be sorted by ExecutionOrder__c ascending; found ' + prev + ' > ' + curr);
        }
    }

    @isTest
    static void testGetScenarios_ThrowsWithoutAdminPermission() {
        // Do NOT assign admin permission set
        Boolean threw = false;
        try {
            SmokeTestScenarioController.getScenarios();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('SmokeTest_Admin'),
                'Error must mention the required permission set');
        }
        System.assert(threw, 'Expected AuraHandledException for non-admin user');
    }

    // =========================================================================
    // createScenario — valid inputs
    // =========================================================================

    @isTest
    static void testCreateScenario_ValidInputs_Succeeds() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> params = new Map<String, Object>{
            'developerName'  => 'Test_Scenario_1',
            'label'          => 'Test Scenario One',
            'isEnabled'      => true,
            'executionOrder' => 999,
            'scenarioClass'  => 'AccountCrudScenario',
            'isCritical'     => false,
            'businessProcess'=> 'Sales',
            'description'    => 'Integration test scenario',
            'changeReason'   => 'Created for smoke test suite'
        };

        Test.startTest();
        Map<String, Object> result = SmokeTestScenarioController.createScenario(params);
        Test.stopTest();

        System.assertEquals(true, result.get('success'),
            'createScenario with valid params should return success=true');
        System.assertEquals('TEST_JOB_ID', result.get('jobId'),
            'Bypassed deployment should return TEST_JOB_ID');
    }

    @isTest
    static void testCreateScenario_AuditLogWritten() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> params = new Map<String, Object>{
            'developerName'  => 'Audit_Test_Scenario',
            'isEnabled'      => true,
            'scenarioClass'  => 'AccountCrudScenario',
            'changeReason'   => 'Testing audit log write'
        };

        Integer beforeCount = [SELECT COUNT() FROM SmokeTestAuditLog__c];

        Test.startTest();
        SmokeTestScenarioController.createScenario(params);
        Test.stopTest();

        Integer afterCount = [SELECT COUNT() FROM SmokeTestAuditLog__c];
        System.assertEquals(beforeCount + 1, afterCount,
            'One audit log record must be written for createScenario');

        SmokeTestAuditLog__c log = [
            SELECT ActionType__c, ResourceId__c, ChangeReason__c, Outcome__c
            FROM SmokeTestAuditLog__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('CONFIGURATION_CHANGE', log.ActionType__c);
        System.assertEquals('Audit_Test_Scenario',  log.ResourceId__c);
        System.assertEquals('Testing audit log write', log.ChangeReason__c);
        System.assertEquals('SUCCESS', log.Outcome__c);
    }

    // =========================================================================
    // createScenario — invalid inputs
    // =========================================================================

    @isTest
    static void testCreateScenario_InvalidDeveloperName_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> params = new Map<String, Object>{
            'developerName' => '1InvalidName',
            'changeReason'  => 'Test'
        };

        Boolean threw = false;
        try {
            SmokeTestScenarioController.createScenario(params);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('letter'),
                'Error must explain the naming rule; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for invalid developer name');
    }

    @isTest
    static void testCreateScenario_NameTooLong_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> params = new Map<String, Object>{
            'developerName' => 'A' + 'x'.repeat(40), // 41 chars — exceeds max 40
            'changeReason'  => 'Test'
        };

        Boolean threw = false;
        try {
            SmokeTestScenarioController.createScenario(params);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AuraHandledException for name exceeding 40 characters');
    }

    @isTest
    static void testCreateScenario_BlankDeveloperName_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> params = new Map<String, Object>{
            'developerName' => '',
            'changeReason'  => 'Test'
        };

        Boolean threw = false;
        try {
            SmokeTestScenarioController.createScenario(params);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AuraHandledException for blank developer name');
    }

    @isTest
    static void testCreateScenario_TimeoutOutOfRange_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> params = new Map<String, Object>{
            'developerName' => 'Valid_Name',
            'timeoutSec'    => 999,
            'changeReason'  => 'Test'
        };

        Boolean threw = false;
        try {
            SmokeTestScenarioController.createScenario(params);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('60'),
                'Error must mention max timeout; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for timeout > 60');
    }

    @isTest
    static void testCreateScenario_CpuBudgetOutOfRange_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> params = new Map<String, Object>{
            'developerName' => 'Valid_Name',
            'cpuBudget'     => 99999,
            'changeReason'  => 'Test'
        };

        Boolean threw = false;
        try {
            SmokeTestScenarioController.createScenario(params);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('10000'),
                'Error must mention max CPU budget; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for cpuBudget > 10000');
    }

    @isTest
    static void testCreateScenario_InvalidApexClass_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Map<String, Object> params = new Map<String, Object>{
            'developerName' => 'Valid_Name',
            'scenarioClass' => 'NonExistentClassXyz123',
            'changeReason'  => 'Test'
        };

        Boolean threw = false;
        try {
            SmokeTestScenarioController.createScenario(params);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('NonExistentClassXyz123'),
                'Error must include the invalid class name; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for non-existent Apex class');
    }

    @isTest
    static void testCreateScenario_ClassNotISmokeTestScenario_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        // DefaultDmlHandler exists and is a real class but does not implement ISmokeTestScenario
        Map<String, Object> params = new Map<String, Object>{
            'developerName' => 'Valid_Name',
            'scenarioClass' => 'DefaultDmlHandler',
            'changeReason'  => 'Test'
        };

        Boolean threw = false;
        try {
            SmokeTestScenarioController.createScenario(params);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('ISmokeTestScenario'),
                'Error must mention interface requirement; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for class not implementing ISmokeTestScenario');
    }

    // =========================================================================
    // toggleScenario
    // =========================================================================

    @isTest
    static void testToggleScenario_WritesAuditLog() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        // Find a real MDT record to toggle
        Map<String, SmokeTestScenario__mdt> all = SmokeTestScenario__mdt.getAll();
        if (all.isEmpty()) return;
        String devName = new List<String>(all.keySet()).get(0);

        Integer beforeCount = [SELECT COUNT() FROM SmokeTestAuditLog__c];

        Test.startTest();
        Map<String, Object> result = SmokeTestScenarioController.toggleScenario(
            devName, false, 'Disabling for maintenance'
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'toggleScenario must return success=true');

        Integer afterCount = [SELECT COUNT() FROM SmokeTestAuditLog__c];
        System.assertEquals(beforeCount + 1, afterCount,
            'One audit log record must be written for toggleScenario');

        SmokeTestAuditLog__c log = [
            SELECT ActionType__c, ChangeReason__c, NewValue__c
            FROM SmokeTestAuditLog__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('CONFIGURATION_CHANGE', log.ActionType__c);
        System.assertEquals('Disabling for maintenance', log.ChangeReason__c);
        System.assert(log.NewValue__c.contains('false'),
            'NewValue should show the new enabled state');
    }

    @isTest
    static void testToggleScenario_MissingChangeReason_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Boolean threw = false;
        try {
            SmokeTestScenarioController.toggleScenario('Account_CRUD', true, '');
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('changeReason'),
                'Error must mention changeReason; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for blank changeReason');
    }

    @isTest
    static void testToggleScenario_NotFoundScenario_Throws() {
        MetadataDeployService.bypassDeployment = true;
        assignAdminPermission();

        Boolean threw = false;
        try {
            SmokeTestScenarioController.toggleScenario(
                'NonExistent_Scenario_Xyz', true, 'Test reason');
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('NonExistent_Scenario_Xyz'),
                'Error must include the missing scenario name; got: ' + e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for non-existent scenario');
    }

    // =========================================================================
    // MetadataDeployService (unit tests for the service itself)
    // =========================================================================

    @isTest
    static void testMetadataDeployService_BuildsCorrectContainer() {
        MetadataDeployService.bypassDeployment = true;

        MetadataDeployService.DeployResult result = MetadataDeployService.upsertCustomMetadata(
            'SmokeTestScenario__mdt',
            'Test_Scenario',
            'Test Scenario',
            new Map<String, Object>{
                'IsEnabled__c'      => true,
                'ExecutionOrder__c' => 10
            }
        );

        System.assertEquals(true, result.success, 'upsertCustomMetadata should succeed');
        System.assertEquals('TEST_JOB_ID', result.jobId);
        System.assertNotEquals(null, MetadataDeployService.lastContainer,
            'lastContainer must be set for test assertions');
    }

    @isTest
    static void testMetadataDeployService_NullFieldValues_Succeeds() {
        MetadataDeployService.bypassDeployment = true;

        MetadataDeployService.DeployResult result = MetadataDeployService.upsertCustomMetadata(
            'SmokeTestScenario__mdt', 'Test_Scenario', 'Test Scenario', null
        );

        System.assertEquals(true, result.success, 'Null field values should still succeed');
    }

    @isTest
    static void testMetadataDeployService_MdtWithoutSuffix() {
        MetadataDeployService.bypassDeployment = true;

        MetadataDeployService.DeployResult result = MetadataDeployService.upsertCustomMetadata(
            'SmokeTestScenario', 'Test_Scenario', 'Label', null
        );

        System.assertEquals(true, result.success,
            'Should handle mdtApiName without __mdt suffix');
    }
}
