/**
 * Unit and integration tests for RoleBasedScenarioExecutor.
 *
 * Test categories:
 *   Profile execution  — System Administrator, Standard User, custom profile
 *   Permission failure — detected and surfaced with specific detail
 *   Non-permission     — non-access exceptions captured as UNEXPECTED_ERROR
 *   Persistence        — SmokeTestResult__c created with RoleProfile__c populated
 *   Permission parsing — PermissionFailureDetail field extraction
 *   Edge cases         — blank profile, profile not found, non-test context guard
 *   Integration        — full executeAsProfile() chain with real profile lookup
 */
@isTest
private class RoleBasedScenarioExecutorTest {

    private static final String SCENARIO_ACCOUNT_CRUD = 'Account_CRUD';
    private static final String SCENARIO_OPP_CRUD     = 'Opportunity_CRUD';
    private static final String SCENARIO_CASE_CREATE  = 'Case_Creation';

    // =========================================================================
    // Helpers
    // =========================================================================

    private static RoleBasedScenarioExecutor executor() {
        return new RoleBasedScenarioExecutor();
    }

    // =========================================================================
    // Test 1 — System Administrator executes scenario successfully (AC2, AC8)
    // =========================================================================

    @isTest
    static void test_SysAdmin_PassScenario_ReturnsPassResult() {
        SmokeTestContext ctx = RoleBasedTestFixtures.makeContext();
        ISmokeTestScenario scenario = new RoleBasedTestFixtures.AlwaysPassScenario(SCENARIO_ACCOUNT_CRUD);

        Test.startTest();
        RoleBasedScenarioExecutor.ScenarioExecutionResult result =
            executor().executeAsProfile(scenario, RoleBasedTestFixtures.PROFILE_SYS_ADMIN, ctx);
        Test.stopTest();

        System.assert(result != null, 'Result must not be null');
        System.assertEquals(RoleBasedTestFixtures.PROFILE_SYS_ADMIN, result.profileName,
            'profileName must match the requested profile');
        System.assertEquals(true, result.isPassed(),
            'Scenario should pass under System Administrator');
        System.assertEquals(null, result.permissionFailureDetail,
            'No permission failure detail should be present for a passing scenario');
        System.assertEquals(false, result.profileNotFound,
            'profileNotFound should be false when profile exists');
    }

    // =========================================================================
    // Test 2 — Standard User scenario returns result with profile name (AC2, AC4)
    // =========================================================================

    @isTest
    static void test_StandardUser_PassScenario_IncludesProfileName() {
        SmokeTestContext ctx = RoleBasedTestFixtures.makeContext();
        ISmokeTestScenario scenario = new RoleBasedTestFixtures.AlwaysPassScenario(SCENARIO_OPP_CRUD);

        Test.startTest();
        RoleBasedScenarioExecutor.ScenarioExecutionResult result =
            executor().executeAsProfile(scenario, RoleBasedTestFixtures.PROFILE_STANDARD_USER, ctx);
        Test.stopTest();

        System.assert(result != null, 'Result must not be null');
        System.assertEquals(RoleBasedTestFixtures.PROFILE_STANDARD_USER, result.profileName,
            'profileName must be Standard User');
        System.assertEquals(SCENARIO_OPP_CRUD, result.scenarioResult.scenarioName,
            'scenarioName must be preserved in the result');
        System.assertNotEquals(null, result.scenarioResult.durationMs,
            'durationMs must be populated');
    }

    // =========================================================================
    // Test 3 — Custom (third MVP) profile execution returns correct profile name (AC2)
    // =========================================================================

    @isTest
    static void test_CustomProfile_ExecutionIncludesCustomProfileName() {
        SmokeTestContext ctx = RoleBasedTestFixtures.makeContext();
        ISmokeTestScenario scenario = new RoleBasedTestFixtures.AlwaysPassScenario(SCENARIO_CASE_CREATE);

        Test.startTest();
        RoleBasedScenarioExecutor.ScenarioExecutionResult result =
            executor().executeAsProfile(scenario, RoleBasedTestFixtures.PROFILE_MIN_ACCESS, ctx);
        Test.stopTest();

        System.assert(result != null, 'Result must not be null');
        System.assertEquals(RoleBasedTestFixtures.PROFILE_MIN_ACCESS, result.profileName,
            'profileName must match the custom (Minimum Access) profile');
    }

    // =========================================================================
    // Test 4 — Permission failure is detected and PermissionFailureDetail populated (AC5)
    // =========================================================================

    @isTest
    static void test_PermissionFailure_DetailIsPopulated() {
        SmokeTestContext ctx = RoleBasedTestFixtures.makeContext();
        ISmokeTestScenario scenario =
            new RoleBasedTestFixtures.PermissionFailScenario(SCENARIO_OPP_CRUD, 'no message');

        Test.startTest();
        RoleBasedScenarioExecutor.ScenarioExecutionResult result =
            executor().executeAsProfile(scenario, RoleBasedTestFixtures.PROFILE_STANDARD_USER, ctx);
        Test.stopTest();

        System.assert(result != null, 'Result must not be null');
        System.assertEquals(false, result.isPassed(),
            'Scenario must fail when NoAccessException is thrown');
        System.assertEquals('PERMISSION_DENIED', result.scenarioResult.errorType,
            'errorType must be PERMISSION_DENIED for access exceptions');
        System.assertEquals(true, result.isPermissionFailure(),
            'isPermissionFailure() must be true when NoAccessException is caught');

        PermissionFailureDetail detail = result.permissionFailureDetail;
        System.assertNotEquals(null, detail, 'PermissionFailureDetail must be populated');
        System.assertEquals(RoleBasedTestFixtures.PROFILE_STANDARD_USER, detail.profileName,
            'PermissionFailureDetail.profileName must match the execution profile');
    }

    // =========================================================================
    // Test 5 — Non-permission exception (NullPointerException) is NOT a permission failure (AC5)
    // =========================================================================

    @isTest
    static void test_NonPermissionException_NotClassifiedAsPermissionFailure() {
        SmokeTestContext ctx = RoleBasedTestFixtures.makeContext();
        ISmokeTestScenario scenario =
            new RoleBasedTestFixtures.BusinessLogicFailScenario(SCENARIO_ACCOUNT_CRUD);

        Test.startTest();
        RoleBasedScenarioExecutor.ScenarioExecutionResult result =
            executor().executeAsProfile(scenario, RoleBasedTestFixtures.PROFILE_SYS_ADMIN, ctx);
        Test.stopTest();

        System.assert(result != null, 'Result must not be null');
        System.assertEquals(false, result.isPassed(), 'Scenario should fail');
        System.assertEquals('UNEXPECTED_ERROR', result.scenarioResult.errorType,
            'Non-permission exceptions must be captured as UNEXPECTED_ERROR, not PERMISSION_DENIED');
        System.assertEquals(false, result.isPermissionFailure(),
            'isPermissionFailure() must be false for non-access exceptions');
        System.assertEquals(null, result.permissionFailureDetail,
            'PermissionFailureDetail must be null for non-permission failures');
    }

    // =========================================================================
    // Test 6 — Profile not found returns profileNotFound=true result (AC3)
    // =========================================================================

    @isTest
    static void test_ProfileNotFound_ReturnsProfileNotFoundResult() {
        SmokeTestContext ctx = RoleBasedTestFixtures.makeContext();
        ISmokeTestScenario scenario =
            new RoleBasedTestFixtures.AlwaysPassScenario(SCENARIO_ACCOUNT_CRUD);

        Test.startTest();
        RoleBasedScenarioExecutor.ScenarioExecutionResult result =
            executor().executeAsProfile(scenario, 'NonExistentProfile_XYZ_999', ctx);
        Test.stopTest();

        System.assert(result != null, 'Result must not be null');
        System.assertEquals(true, result.profileNotFound,
            'profileNotFound must be true when the Profile is not in the org');
        System.assertEquals('PROFILE_NOT_FOUND', result.scenarioResult.errorType,
            'errorType must be PROFILE_NOT_FOUND');
        System.assertEquals(false, result.isPassed(), 'Result should not be passing');
    }

    // =========================================================================
    // Test 7 — Blank profile name returns error result gracefully (edge case)
    // =========================================================================

    @isTest
    static void test_BlankProfileName_ReturnsErrorResult() {
        SmokeTestContext ctx = RoleBasedTestFixtures.makeContext();
        ISmokeTestScenario scenario =
            new RoleBasedTestFixtures.AlwaysPassScenario(SCENARIO_ACCOUNT_CRUD);

        Test.startTest();
        RoleBasedScenarioExecutor.ScenarioExecutionResult result =
            executor().executeAsProfile(scenario, '   ', ctx);
        Test.stopTest();

        System.assert(result != null, 'Result must not be null');
        System.assertEquals('INVALID_PROFILE', result.scenarioResult.errorType,
            'Blank profile name should return INVALID_PROFILE errorType');
        System.assertEquals(false, result.isPassed(), 'Blank profile result should not pass');
    }

    // =========================================================================
    // Test 8 — Result persisted to SmokeTestResult__c with RoleProfile__c set (AC6)
    // =========================================================================

    @isTest
    static void test_PersistResult_PopulatesRoleProfileField() {
        SmokeTestExecution__c exec = RoleBasedTestFixtures.makeExecution();
        SmokeTestContext ctx = new SmokeTestContext(exec.Id, null, new Map<String, Object>());
        ISmokeTestScenario scenario =
            new RoleBasedTestFixtures.AlwaysPassScenario(SCENARIO_ACCOUNT_CRUD);

        RoleBasedScenarioExecutor exec2 = executor();

        Test.startTest();
        RoleBasedScenarioExecutor.ScenarioExecutionResult result =
            exec2.executeAsProfile(scenario, RoleBasedTestFixtures.PROFILE_STANDARD_USER, ctx);
        SmokeTestResult__c rec = exec2.persistResult(result, exec.Id, 1);
        Test.stopTest();

        System.assertNotEquals(null, rec.Id, 'Persisted record must have an Id');

        SmokeTestResult__c queried = [
            SELECT ScenarioName__c, Status__c, RoleProfile__c, ExecutionOrder__c
            FROM   SmokeTestResult__c
            WHERE  Id = :rec.Id
        ];
        System.assertEquals(SCENARIO_ACCOUNT_CRUD, queried.ScenarioName__c,
            'ScenarioName must match the executed scenario');
        System.assertEquals('Pass', queried.Status__c,
            'Status must be Pass for a passing scenario');
        System.assertEquals(RoleBasedTestFixtures.PROFILE_STANDARD_USER, queried.RoleProfile__c,
            'RoleProfile__c must be populated with the execution profile name');
        System.assertEquals(1, (Integer) queried.ExecutionOrder__c,
            'ExecutionOrder must match the passed order');
    }

    // =========================================================================
    // Test 9 — extractObjectName parses entity type pattern (AC5)
    // =========================================================================

    @isTest
    static void test_ExtractObjectName_EntityTypePattern() {
        String msg = "Entity type 'Opportunity' is not accessible (Edit)";
        System.assertEquals('Opportunity',
            RoleBasedScenarioExecutor.extractObjectName(msg),
            'extractObjectName should parse "Entity type \'Opportunity\'"');
    }

    // =========================================================================
    // Test 10 — extractFieldName parses object.field pattern (AC5)
    // =========================================================================

    @isTest
    static void test_ExtractFieldName_DotNotationPattern() {
        String msg = "field 'Opportunity.Amount__c' is not accessible";
        System.assertEquals('Amount__c',
            RoleBasedScenarioExecutor.extractFieldName(msg),
            'extractFieldName should parse "Opportunity.Amount__c"');
    }

    // =========================================================================
    // Test 11 — extractPermissionType detects Edit from "(Edit)" suffix (AC5)
    // =========================================================================

    @isTest
    static void test_ExtractPermissionType_EditSuffix() {
        System.assertEquals('Edit',
            RoleBasedScenarioExecutor.extractPermissionType("Entity type 'Opp' is not accessible (Edit)"),
            'Permission type should be Edit');
    }

    // =========================================================================
    // Test 12 — extractPermissionType detects Create (AC5)
    // =========================================================================

    @isTest
    static void test_ExtractPermissionType_Create() {
        System.assertEquals('Create',
            RoleBasedScenarioExecutor.extractPermissionType("Entity type 'Case' is not accessible (Create)"),
            'Permission type should be Create');
    }

    // =========================================================================
    // Test 13 — extractPermissionType detects Delete (AC5)
    // =========================================================================

    @isTest
    static void test_ExtractPermissionType_Delete() {
        System.assertEquals('Delete',
            RoleBasedScenarioExecutor.extractPermissionType("Entity type 'Case' is not deletable"),
            'Permission type should be Delete');
    }

    // =========================================================================
    // Test 14 — Leading/trailing whitespace in profile name is trimmed (edge case)
    // =========================================================================

    @isTest
    static void test_ProfileNameTrimmed_BeforeQuery() {
        SmokeTestContext ctx = RoleBasedTestFixtures.makeContext();
        ISmokeTestScenario scenario =
            new RoleBasedTestFixtures.AlwaysPassScenario(SCENARIO_ACCOUNT_CRUD);

        Test.startTest();
        // Profile name with whitespace should still find the profile
        RoleBasedScenarioExecutor.ScenarioExecutionResult result =
            executor().executeAsProfile(scenario, '  System Administrator  ', ctx);
        Test.stopTest();

        System.assertEquals('System Administrator', result.profileName,
            'profileName in result must be the trimmed profile name');
        System.assertEquals(false, result.profileNotFound,
            'Whitespace-padded profile name should be found after trimming');
    }

    // =========================================================================
    // Test 15 — Convenience overload (no SmokeTestContext) creates execution and runs (AC1)
    // =========================================================================

    @isTest
    static void test_ConvenienceOverload_CreatesExecutionAndRuns() {
        ISmokeTestScenario scenario =
            new RoleBasedTestFixtures.AlwaysPassScenario(SCENARIO_ACCOUNT_CRUD);

        Test.startTest();
        RoleBasedScenarioExecutor.ScenarioExecutionResult result =
            executor().executeAsProfile(scenario, RoleBasedTestFixtures.PROFILE_SYS_ADMIN);
        Test.stopTest();

        System.assert(result != null, 'Result must not be null');
        System.assertEquals(RoleBasedTestFixtures.PROFILE_SYS_ADMIN, result.profileName,
            'profileName must be populated');
        System.assertEquals(true, result.isPassed(), 'Scenario should pass under System Administrator');
    }

    // =========================================================================
    // Test 16 — System integration: full flow with real SmokeTestExecution__c (AC9)
    // =========================================================================

    @isTest
    static void test_Integration_FullFlow_ResultWithProfileAndStatus() {
        SmokeTestExecution__c exec = RoleBasedTestFixtures.makeExecution();
        SmokeTestContext ctx = new SmokeTestContext(exec.Id, null, new Map<String, Object>());
        ISmokeTestScenario scenario =
            new RoleBasedTestFixtures.AlwaysPassScenario(SCENARIO_ACCOUNT_CRUD);

        RoleBasedScenarioExecutor rbe = executor();

        Test.startTest();
        RoleBasedScenarioExecutor.ScenarioExecutionResult result =
            rbe.executeAsProfile(scenario, RoleBasedTestFixtures.PROFILE_SYS_ADMIN, ctx);
        SmokeTestResult__c rec = rbe.persistResult(result, exec.Id, 1);
        Test.stopTest();

        // Verify all AC4 fields are present in the result
        System.assertEquals(SCENARIO_ACCOUNT_CRUD, result.scenarioResult.scenarioName,
            'Integration: scenario name must be in result');
        System.assertEquals(RoleBasedTestFixtures.PROFILE_SYS_ADMIN, result.profileName,
            'Integration: profile name must be in result');
        System.assertEquals(true, result.isPassed(),
            'Integration: result should be passing');
        System.assertNotEquals(null, result.scenarioResult.durationMs,
            'Integration: durationMs must be populated');

        // Verify SmokeTestResult__c has RoleProfile__c set
        SmokeTestResult__c queried = [
            SELECT Status__c, RoleProfile__c FROM SmokeTestResult__c WHERE Id = :rec.Id
        ];
        System.assertEquals('Pass', queried.Status__c, 'Integration: Status should be Pass');
        System.assertEquals(RoleBasedTestFixtures.PROFILE_SYS_ADMIN, queried.RoleProfile__c,
            'Integration: RoleProfile__c must be set on the persisted result record');
    }
}
