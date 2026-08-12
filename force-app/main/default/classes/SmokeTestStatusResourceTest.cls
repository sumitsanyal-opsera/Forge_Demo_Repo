/**
 * Unit and integration tests for SmokeTestStatusResource.
 *
 * Test categories:
 *   Complete execution     — 200, all scenarios with results
 *   In-progress execution  — 200, partial results + pending placeholders
 *   Queued execution       — 200, all scenarios pending
 *   Invalid executionId    — 400 VALIDATION_ERROR
 *   Not found executionId  — 404 NOT_FOUND
 *   Missing permission     — 403 FORBIDDEN
 *   Duration calculation   — in-progress vs completed duration logic
 */
@isTest
private class SmokeTestStatusResourceTest {

    // =========================================================================
    // Helpers
    // =========================================================================

    private static void setupGetContext(String executionId) {
        ApiResponseTestHelper.setUpRestContext();
        RestContext.request.httpMethod = 'GET';
        RestContext.request.requestURI =
            '/services/apexrest/smoketest/v1/status/' + executionId;
    }

    private static Map<String, Object> deserializeBody() {
        return (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
    }

    private static SmokeTestExecution__c insertExecution(
        String status,
        Integer totalScenarios,
        Long durationMs
    ) {
        SmokeTestExecution__c exec = new SmokeTestExecution__c(
            Status__c         = status,
            StartTime__c      = DateTime.now().addSeconds(-30),
            TotalScenarios__c = totalScenarios,
            ExecutionTimeMs__c= durationMs
        );
        insert exec;
        return exec;
    }

    private static SmokeTestResult__c insertResult(
        Id executionId,
        String scenarioName,
        String status,
        Long durationMs,
        Integer order
    ) {
        SmokeTestResult__c r = new SmokeTestResult__c(
            Execution__c       = executionId,
            ScenarioName__c    = scenarioName,
            Status__c          = status,
            ExecutionTimeMs__c = durationMs,
            ExecutionOrder__c  = order
        );
        insert r;
        return r;
    }

    private static void resetOverrides() {
        SmokeTestStatusResource.permissionCheckOverride = null;
    }

    // =========================================================================
    // Test 1 — Complete execution: 3 results, all scenarios returned
    // =========================================================================

    @isTest
    static void testCompleteExecution_returns200WithAllScenarios() {
        SmokeTestStatusResource.permissionCheckOverride = true;

        SmokeTestExecution__c exec = insertExecution('Completed', 3, 1500L);
        insertResult(exec.Id, 'Scenario_A', 'Pass',    100L, 0);
        insertResult(exec.Id, 'Scenario_B', 'Fail',    200L, 1);
        insertResult(exec.Id, 'Scenario_C', 'Timeout', 300L, 2);

        setupGetContext(exec.Id);

        Test.startTest();
        SmokeTestStatusResource.doGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Complete execution should return HTTP 200');

        Map<String, Object> body = deserializeBody();
        System.assertEquals(String.valueOf(exec.Id), body.get('executionId'),
            'executionId should match the queried record');
        System.assertEquals('complete', body.get('status'),
            'Completed status should normalize to complete');
        System.assertEquals(1500L, (Long) body.get('executionDurationMs'),
            'Terminal execution should use stored ExecutionTimeMs__c');

        List<Object> scenarios = (List<Object>) body.get('scenarios');
        System.assertEquals(3, scenarios.size(),
            'Should have 3 scenario results for completed execution');

        // Verify first result order and result value
        Map<String, Object> first = (Map<String, Object>) scenarios[0];
        System.assertEquals('Scenario_A', first.get('name'),
            'First scenario should be Scenario_A (order=0)');
        System.assertEquals('pass', first.get('result'),
            'Pass status should be lowercased to pass');

        System.assert(body.containsKey('timestamp'),
            'Response must contain timestamp');

        resetOverrides();
    }

    // =========================================================================
    // Test 2 — In-progress execution: 2 of 3 completed, 1 pending
    // =========================================================================

    @isTest
    static void testInProgressExecution_showsCompletedAndPending() {
        SmokeTestStatusResource.permissionCheckOverride = true;

        SmokeTestExecution__c exec = insertExecution('In Progress', 3, null);
        insertResult(exec.Id, 'Scenario_A', 'Pass', 100L, 0);
        insertResult(exec.Id, 'Scenario_B', 'Fail', 200L, 1);

        setupGetContext(exec.Id);

        Test.startTest();
        SmokeTestStatusResource.doGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'In-progress execution should return HTTP 200');

        Map<String, Object> body = deserializeBody();
        System.assertEquals('in_progress', body.get('status'),
            'In Progress status should normalize to in_progress');

        List<Object> scenarios = (List<Object>) body.get('scenarios');
        System.assertEquals(3, scenarios.size(),
            'Should have 2 completed + 1 pending = 3 scenario entries');

        // Last entry should be pending
        Map<String, Object> pendingEntry = (Map<String, Object>) scenarios[2];
        System.assertEquals('pending', pendingEntry.get('result'),
            'Remaining scenario should have result=pending');
        System.assertEquals(null, pendingEntry.get('durationMs'),
            'Pending scenario should have null durationMs');

        resetOverrides();
    }

    // =========================================================================
    // Test 3 — Queued execution: no results yet, all scenarios pending
    // =========================================================================

    @isTest
    static void testQueuedExecution_allScenariosPending() {
        SmokeTestStatusResource.permissionCheckOverride = true;

        SmokeTestExecution__c exec = insertExecution('Queued', 5, null);

        setupGetContext(exec.Id);

        Test.startTest();
        SmokeTestStatusResource.doGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Queued execution should return HTTP 200');

        Map<String, Object> body = deserializeBody();
        System.assertEquals('queued', body.get('status'),
            'Queued status should normalize to queued');

        List<Object> scenarios = (List<Object>) body.get('scenarios');
        System.assertEquals(5, scenarios.size(),
            'Queued execution with 5 total scenarios should have 5 pending entries');

        for (Object s : scenarios) {
            Map<String, Object> scenario = (Map<String, Object>) s;
            System.assertEquals('pending', scenario.get('result'),
                'All scenarios in a queued execution should be pending');
        }

        resetOverrides();
    }

    // =========================================================================
    // Test 4 — Invalid executionId format → 400
    // =========================================================================

    @isTest
    static void testInvalidExecutionId_returns400() {
        SmokeTestStatusResource.permissionCheckOverride = true;

        setupGetContext('INVALID_ID');

        Test.startTest();
        SmokeTestStatusResource.doGet();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Invalid executionId format should return HTTP 400');

        Map<String, Object> body = deserializeBody();
        ApiResponseTestHelper.assertErrorFields(body);
        System.assertEquals('VALIDATION_ERROR', body.get('errorCode'),
            'Error code should be VALIDATION_ERROR for invalid ID format');

        resetOverrides();
    }

    // =========================================================================
    // Test 5 — Valid format but non-existent executionId → 404
    // =========================================================================

    @isTest
    static void testNotFoundExecutionId_returns404() {
        SmokeTestStatusResource.permissionCheckOverride = true;

        // Insert and delete a record to get a valid but now non-existent Id
        SmokeTestExecution__c dummy = new SmokeTestExecution__c(
            Status__c = 'Queued', TotalScenarios__c = 0
        );
        insert dummy;
        Id deletedId = dummy.Id;
        delete dummy;

        setupGetContext(deletedId);

        Test.startTest();
        SmokeTestStatusResource.doGet();
        Test.stopTest();

        System.assertEquals(404, RestContext.response.statusCode,
            'Non-existent executionId should return HTTP 404');

        Map<String, Object> body = deserializeBody();
        ApiResponseTestHelper.assertErrorFields(body);
        System.assertEquals('NOT_FOUND', body.get('errorCode'),
            'Error code should be NOT_FOUND when record does not exist');

        resetOverrides();
    }

    // =========================================================================
    // Test 6 — Missing permission → 403
    // =========================================================================

    @isTest
    static void testMissingPermission_returns403() {
        SmokeTestStatusResource.permissionCheckOverride = false;

        SmokeTestExecution__c exec = insertExecution('Completed', 0, 100L);
        setupGetContext(exec.Id);

        Test.startTest();
        SmokeTestStatusResource.doGet();
        Test.stopTest();

        System.assertEquals(403, RestContext.response.statusCode,
            'User lacking permission should receive HTTP 403');

        Map<String, Object> body = deserializeBody();
        ApiResponseTestHelper.assertErrorFields(body);
        System.assertEquals('FORBIDDEN', body.get('errorCode'),
            'Error code should be FORBIDDEN for missing permission');

        resetOverrides();
    }

    // =========================================================================
    // Test 7 — Duration calculation: complete uses stored ExecutionTimeMs__c
    // =========================================================================

    @isTest
    static void testDurationCalculation_completedUsesStoredValue() {
        SmokeTestStatusResource.permissionCheckOverride = true;

        SmokeTestExecution__c completedExec = insertExecution('Completed', 0, 5000L);
        setupGetContext(completedExec.Id);

        Test.startTest();
        SmokeTestStatusResource.doGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Completed execution status call should return 200');
        Map<String, Object> body = deserializeBody();
        System.assertEquals(5000L, (Long) body.get('executionDurationMs'),
            'Completed execution should use stored ExecutionTimeMs__c (5000ms)');

        resetOverrides();
    }

    // =========================================================================
    // Test 8 (bonus) — In-progress duration is computed live from StartTime__c
    // =========================================================================

    @isTest
    static void testDurationCalculation_inProgressComputedFromStartTime() {
        SmokeTestStatusResource.permissionCheckOverride = true;

        SmokeTestExecution__c exec = new SmokeTestExecution__c(
            Status__c          = 'In Progress',
            StartTime__c       = DateTime.now().addSeconds(-10),
            TotalScenarios__c  = 0,
            ExecutionTimeMs__c = null
        );
        insert exec;
        setupGetContext(exec.Id);

        Test.startTest();
        SmokeTestStatusResource.doGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'In-progress execution should return HTTP 200');
        Map<String, Object> body = deserializeBody();
        Long liveDuration = (Long) body.get('executionDurationMs');
        System.assert(liveDuration >= 0,
            'In-progress duration should be non-negative; computed: ' + liveDuration);

        resetOverrides();
    }

    // =========================================================================
    // Test 8 — Response contains all required fields per acceptance criteria
    // =========================================================================

    @isTest
    static void testResponseShape_containsAllRequiredFields() {
        SmokeTestStatusResource.permissionCheckOverride = true;

        SmokeTestExecution__c exec = insertExecution('Completed', 1, 250L);
        insertResult(exec.Id, 'Scenario_X', 'Pass', 250L, 0);

        setupGetContext(exec.Id);

        Test.startTest();
        SmokeTestStatusResource.doGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Should return 200 for valid complete execution');
        System.assertNotEquals(null, RestContext.response.responseBody,
            'Response body must not be null');

        Map<String, Object> body = deserializeBody();
        System.assert(body.containsKey('executionId'),     'Response must contain executionId');
        System.assert(body.containsKey('status'),          'Response must contain status');
        System.assert(body.containsKey('scenarios'),       'Response must contain scenarios');
        System.assert(body.containsKey('executionDurationMs'), 'Response must contain executionDurationMs');
        System.assert(body.containsKey('timestamp'),       'Response must contain timestamp');

        // Verify scenario shape
        List<Object> scenarios = (List<Object>) body.get('scenarios');
        System.assertEquals(1, scenarios.size(), 'Should have 1 scenario result');
        Map<String, Object> scenario = (Map<String, Object>) scenarios[0];
        System.assert(scenario.containsKey('name'),       'Scenario must contain name');
        System.assert(scenario.containsKey('result'),     'Scenario must contain result');
        System.assert(scenario.containsKey('durationMs'), 'Scenario must contain durationMs');

        resetOverrides();
    }
}
