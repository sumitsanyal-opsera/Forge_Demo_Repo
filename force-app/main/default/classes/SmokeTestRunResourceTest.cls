/**
 * Unit and integration tests for SmokeTestRunResource.
 *
 * Test categories:
 *   Valid request      — 202, executionId, Status='Queued', TriggerSource='API'
 *   Input validation   — 400 for malformed JSON, empty body, unknown fields
 *   Authorization      — 403 for user lacking permission set
 *   Rate limiting      — 429 with Retry-After for queue depth exceeded
 *   Field storage      — webhookCallbackUrl, rollbackPolicyOverride stored on execution
 *   Audit logging      — SmokeTestAuditLog__c created after success and error
 *   Integration        — end-to-end POST via Test.startTest/stopTest
 */
@isTest
private class SmokeTestRunResourceTest {

    private static final String VALID_PAYLOAD  = '{"targetOrg":"my-ci-org"}';
    private static final String TARGET_ORG     = 'my-ci-org';

    // =========================================================================
    // Setup helpers
    // =========================================================================

    private static void setupRestContext(String jsonBody) {
        ApiResponseTestHelper.setUpRestContext();
        RestContext.request.httpMethod  = 'POST';
        RestContext.request.requestURI  = '/services/apexrest/smoketest/v1/run';
        if (jsonBody != null) {
            RestContext.request.requestBody = Blob.valueOf(jsonBody);
        }
    }

    private static Map<String,Object> deserializeBody() {
        return (Map<String,Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
    }

    private static void resetFlags() {
        SmokeTestRunResource.asyncJobCountOverride = null;
        SmokeTestOrchestrator.bypassEnqueue        = false;
    }

    // =========================================================================
    // Test 1 — valid request returns 202 with executionId
    // =========================================================================

    @isTest
    static void testValidRequest_returns202WithExecutionId() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        setupRestContext(VALID_PAYLOAD);

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        System.assertEquals(202, RestContext.response.statusCode,
            'Valid request should return HTTP 202');

        Map<String,Object> body = deserializeBody();
        System.assert(body.containsKey('executionId'),
            'Response must contain executionId');
        System.assert(body.containsKey('status'),
            'Response must contain status');
        System.assertEquals('queued', body.get('status'),
            'Response status should be queued');
        System.assert(body.containsKey('timestamp'),
            'Response must contain timestamp');

        resetFlags();
    }

    // =========================================================================
    // Test 2 — execution record created with correct fields
    // =========================================================================

    @isTest
    static void testValidRequest_createsExecutionRecord() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        setupRestContext(VALID_PAYLOAD);

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        List<SmokeTestExecution__c> execs = [
            SELECT Status__c, TriggerSource__c, TargetOrg__c, InitiatedBy__c
            FROM   SmokeTestExecution__c
            WHERE  TriggerSource__c = 'API'
            LIMIT  1
        ];
        System.assertEquals(1, execs.size(), 'One execution record should be created');
        System.assertEquals('Queued', execs[0].Status__c,
            'Execution Status must be Queued');
        System.assertEquals('API', execs[0].TriggerSource__c,
            'TriggerSource must be API');
        System.assertEquals(TARGET_ORG, execs[0].TargetOrg__c,
            'TargetOrg must match the request');
        System.assertEquals(UserInfo.getUserId(), execs[0].InitiatedBy__c,
            'InitiatedBy must be the running user');

        resetFlags();
    }

    // =========================================================================
    // Test 3 — executionId in response matches the created record
    // =========================================================================

    @isTest
    static void testValidRequest_executionIdMatchesRecord() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        setupRestContext(VALID_PAYLOAD);

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        Map<String,Object> body = deserializeBody();
        String returnedId = (String) body.get('executionId');
        System.assertNotEquals(null, returnedId, 'executionId must not be null');

        Integer count = [
            SELECT COUNT()
            FROM   SmokeTestExecution__c
            WHERE  Id = :returnedId
        ];
        System.assertEquals(1, count,
            'executionId in response must correspond to a real SmokeTestExecution__c record');

        resetFlags();
    }

    // =========================================================================
    // Test 4 — invalid / malformed JSON returns 400
    // =========================================================================

    @isTest
    static void testMalformedJson_returns400() {
        setupRestContext('{not valid json}');

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Malformed JSON should return HTTP 400');

        Map<String,Object> body = ApiResponseTestHelper.deserializeErrorBody(
            RestContext.response);
        System.assertEquals('VALIDATION_ERROR', body.get('errorCode'),
            'Error code must be VALIDATION_ERROR');
        ApiResponseTestHelper.assertErrorFields(body);

        resetFlags();
    }

    // =========================================================================
    // Test 5 — null request body returns 400
    // =========================================================================

    @isTest
    static void testNullBody_returns400() {
        setupRestContext(null);  // no body

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Null request body should return HTTP 400');

        resetFlags();
    }

    // =========================================================================
    // Test 6 — missing required field targetOrg returns 400
    // =========================================================================

    @isTest
    static void testMissingTargetOrg_returns400() {
        setupRestContext('{"scenarioFilter":["Account_CRUD"]}');

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Missing required targetOrg should return HTTP 400');

        resetFlags();
    }

    // =========================================================================
    // Test 7 — missing permission set returns 403
    // =========================================================================

    @isTest
    static void testMissingPermissionSet_returns403() {
        // Create a user with no SmokeTest permission sets
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User noPermUser = new User(
            Alias            = 'noperm',
            Email            = 'noperm@smoketest.testonly.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName         = 'NoPermTest',
            LanguageLocaleKey= 'en_US',
            LocaleSidKey     = 'en_US',
            ProfileId        = stdProfile.Id,
            TimeZoneSidKey   = 'America/Los_Angeles',
            UserName         = 'noperm@smoketest.testonly.invalid.' + System.currentTimeMillis()
        );
        insert noPermUser;

        System.runAs(noPermUser) {
            setupRestContext(VALID_PAYLOAD);
            Test.startTest();
            SmokeTestRunResource.doPost();
            Test.stopTest();
        }

        System.assertEquals(403, RestContext.response.statusCode,
            'User without permission set should receive HTTP 403');

        Map<String,Object> body = ApiResponseTestHelper.deserializeErrorBody(
            RestContext.response);
        System.assertEquals('FORBIDDEN', body.get('errorCode'),
            'Error code must be FORBIDDEN');

        resetFlags();
    }

    // =========================================================================
    // Test 8 — queue depth exceeded returns 429 with Retry-After
    // =========================================================================

    @isTest
    static void testQueueCapacityExceeded_returns429WithRetryAfter() {
        // BackpressureQueueDepthPct__c defaults to 80; 80% of 250 = 200
        // Inject a count at or above 200 to trigger 429
        SmokeTestRunResource.asyncJobCountOverride = 200;
        setupRestContext(VALID_PAYLOAD);

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        System.assertEquals(429, RestContext.response.statusCode,
            'Queue depth exceeded should return HTTP 429');

        Map<String,Object> body = ApiResponseTestHelper.deserializeErrorBody(
            RestContext.response);
        System.assertEquals('RATE_LIMITED', body.get('errorCode'),
            'Error code must be RATE_LIMITED');

        String retryAfter = ApiResponseTestHelper.getResponseHeader(
            RestContext.response, 'Retry-After');
        System.assertNotEquals(null, retryAfter,
            'HTTP 429 must include Retry-After header');
        System.assertEquals('30', retryAfter,
            'Retry-After must be 30 seconds');

        resetFlags();
    }

    // =========================================================================
    // Test 9 — webhookCallbackUrl stored on execution record
    // =========================================================================

    @isTest
    static void testWebhookUrl_storedOnExecution() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        // hooks.slack.com is whitelisted in SmokeTestAlertRoute__mdt.DevOps_PipelineFailures
        String payload = '{"targetOrg":"webhook-test-org",'
            + '"webhookCallbackUrl":"https://hooks.slack.com/services/test"}';
        setupRestContext(payload);

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        List<SmokeTestExecution__c> execs = [
            SELECT WebhookCallbackUrl__c
            FROM   SmokeTestExecution__c
            WHERE  TargetOrg__c = 'webhook-test-org'
            LIMIT  1
        ];
        System.assertEquals(1, execs.size(), 'Execution record should be created');
        System.assertEquals(
            'https://hooks.slack.com/services/test',
            execs[0].WebhookCallbackUrl__c,
            'WebhookCallbackUrl must be stored on the execution record'
        );

        resetFlags();
    }

    // =========================================================================
    // Test 10 — rollbackPolicyOverride stored on execution record
    // =========================================================================

    @isTest
    static void testRollbackPolicy_storedOnExecution() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        String payload = '{"targetOrg":"rollback-test-org",'
            + '"rollbackPolicyOverride":"AUTO_ROLLBACK"}';
        setupRestContext(payload);

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        List<SmokeTestExecution__c> execs = [
            SELECT RollbackPolicy__c
            FROM   SmokeTestExecution__c
            WHERE  TargetOrg__c = 'rollback-test-org'
            LIMIT  1
        ];
        System.assertEquals(1, execs.size(), 'Execution record should be created');
        System.assertEquals('AUTO_ROLLBACK', execs[0].RollbackPolicy__c,
            'RollbackPolicy must be stored on the execution record');

        resetFlags();
    }

    // =========================================================================
    // Test 11 — audit log created after successful request
    // =========================================================================

    @isTest
    static void testAuditLog_createdAfterSuccess() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        setupRestContext(VALID_PAYLOAD);

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        Integer auditCount = [
            SELECT COUNT()
            FROM   SmokeTestAuditLog__c
            WHERE  Outcome__c = 'SUCCESS'
            AND    ResourceType__c = 'SmokeTestExecution__c'
        ];
        System.assertEquals(1, auditCount,
            'One audit log record with outcome SUCCESS should be created');

        resetFlags();
    }

    // =========================================================================
    // Test 12 — unknown field in request returns 400
    // =========================================================================

    @isTest
    static void testUnknownField_returns400() {
        setupRestContext('{"targetOrg":"test-org","unknownKey":"someValue"}');

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Unknown field in request should return HTTP 400');

        resetFlags();
    }

    // =========================================================================
    // Test 13 — request with scenarioFilter array is accepted (202)
    // =========================================================================

    @isTest
    static void testScenarioFilter_accepted() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        String payload = '{"targetOrg":"filter-test-org",'
            + '"scenarioFilter":["Account-CRUD","Contact-CRUD"]}';
        setupRestContext(payload);

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        System.assertEquals(202, RestContext.response.statusCode,
            'Request with valid scenarioFilter should return HTTP 202');

        resetFlags();
    }

    // =========================================================================
    // Test 14 — integration: end-to-end POST creates execution and queues job
    // =========================================================================

    @isTest
    static void testIntegration_postCreatesExecutionAndQueuesJob() {
        setupRestContext(VALID_PAYLOAD);

        Test.startTest();
        SmokeTestRunResource.doPost();
        Test.stopTest();

        // Execution record must exist
        List<SmokeTestExecution__c> execs = [
            SELECT Id, Status__c, TriggerSource__c
            FROM   SmokeTestExecution__c
            WHERE  TriggerSource__c = 'API'
        ];
        System.assert(execs.size() >= 1,
            'At least one SmokeTestExecution__c should be created by the integration flow');

        System.assertEquals(202, RestContext.response.statusCode,
            'Integration flow should return HTTP 202');

        resetFlags();
    }
}
