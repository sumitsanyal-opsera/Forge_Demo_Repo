/**
 * Unit tests for SmokeTestApiResponse — standardized REST response builder.
 *
 * Test categories:
 *   Error status codes  (6)  — 400, 401, 403, 404, 429, 500
 *   Success responses   (3)  — 200 acknowledgment, 200 full results, 201 creation
 *   Headers             (2)  — X-API-Version on all, Retry-After on 429
 *   Security            (2)  — error500 no stack trace, referenceId uniqueness
 *   Edge cases          (4)  — null RestContext, long message, null errorCode, null message
 */
@isTest
private class SmokeTestApiResponseTest {

    // =========================================================================
    // Error status codes
    // =========================================================================

    @isTest
    static void testError400SetsCorrectStatusAndBody() {
        ApiResponseTestHelper.setUpRestContext();

        Test.startTest();
        SmokeTestApiResponse.error400()
            .withErrorCode('INVALID_INPUT')
            .withMessage('Scenario name contains invalid characters. Allowed: alphanumeric, underscore, hyphen.')
            .send();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(400, res.statusCode, 'HTTP status should be 400');

        Map<String, Object> body = ApiResponseTestHelper.deserializeErrorBody(res);
        ApiResponseTestHelper.assertErrorFields(body);
        System.assertEquals('INVALID_INPUT', body.get('errorCode'), 'errorCode should match');
    }

    @isTest
    static void testError401SetsCorrectStatusAndBody() {
        ApiResponseTestHelper.setUpRestContext();

        Test.startTest();
        SmokeTestApiResponse.error401()
            .withErrorCode('UNAUTHORIZED')
            .withMessage('Authentication is required to access this endpoint. Provide a valid session token.')
            .send();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(401, res.statusCode, 'HTTP status should be 401');

        Map<String, Object> body = ApiResponseTestHelper.deserializeErrorBody(res);
        ApiResponseTestHelper.assertErrorFields(body);
        System.assertEquals('UNAUTHORIZED', body.get('errorCode'), 'errorCode should match');
    }

    @isTest
    static void testError403SetsCorrectStatusAndBody() {
        ApiResponseTestHelper.setUpRestContext();

        Test.startTest();
        SmokeTestApiResponse.error403()
            .withErrorCode('FORBIDDEN')
            .withMessage('You do not have permission to trigger smoke test executions. Contact your Salesforce administrator.')
            .send();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(403, res.statusCode, 'HTTP status should be 403');

        Map<String, Object> body = ApiResponseTestHelper.deserializeErrorBody(res);
        ApiResponseTestHelper.assertErrorFields(body);
        System.assertEquals('FORBIDDEN', body.get('errorCode'), 'errorCode should match');
    }

    @isTest
    static void testError404SetsCorrectStatusAndBody() {
        ApiResponseTestHelper.setUpRestContext();

        Test.startTest();
        SmokeTestApiResponse.error404()
            .withErrorCode('EXECUTION_NOT_FOUND')
            .withMessage('No smoke test execution found with the provided ID. Verify the executionId and try again.')
            .send();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(404, res.statusCode, 'HTTP status should be 404');

        Map<String, Object> body = ApiResponseTestHelper.deserializeErrorBody(res);
        ApiResponseTestHelper.assertErrorFields(body);
        System.assertEquals('EXECUTION_NOT_FOUND', body.get('errorCode'), 'errorCode should match');
    }

    @isTest
    static void testError429SetsRetryAfterHeader() {
        ApiResponseTestHelper.setUpRestContext();

        Test.startTest();
        SmokeTestApiResponse.error429()
            .withErrorCode('RATE_LIMIT_EXCEEDED')
            .withMessage('Too many concurrent executions. Retry after 30 seconds.')
            .withRetryAfter(30)
            .send();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(429, res.statusCode, 'HTTP status should be 429');

        String retryAfter = ApiResponseTestHelper.getResponseHeader(res, 'Retry-After');
        System.assertEquals('30', retryAfter, 'Retry-After header should be present with value 30');

        Map<String, Object> body = ApiResponseTestHelper.deserializeErrorBody(res);
        ApiResponseTestHelper.assertErrorFields(body);
    }

    @isTest
    static void testError500GeneratesUniqueReferenceId() {
        Test.startTest();
        // Generate two referenceIds and verify they are distinct
        String refId1 = SmokeTestApiResponse.generateReferenceId();
        String refId2 = SmokeTestApiResponse.generateReferenceId();
        Test.stopTest();

        System.assertNotEquals(refId1, refId2,
            'Two consecutive referenceIds must be unique (collision-resistant)');
        System.assertEquals(32, refId1.length(),
            'referenceId must be 32 hex characters');
        System.assert(refId1.isAlphanumeric(),
            'referenceId must contain only alphanumeric characters (lowercase hex)');
    }

    // =========================================================================
    // Security: no stack trace leakage
    // =========================================================================

    @isTest
    static void testError500DoesNotLeakStackTrace() {
        ApiResponseTestHelper.setUpRestContext();

        // Simulate a message that contains Apex stack trace patterns
        String leakyMessage =
            'An error occurred.\n' +
            'Class.SmokeTestOrchestrator.execute: line 42, column 1\n' +
            'Trigger.DeploymentCompleteTrigger: line 7, column 1\n' +
            'at line 12, column 5';

        Test.startTest();
        SmokeTestApiResponse.error500()
            .withErrorCode('INTERNAL_ERROR')
            .withMessage(leakyMessage)
            .send();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(500, res.statusCode, 'HTTP status should be 500');

        String responseBody = res.responseBody.toString();
        ApiResponseTestHelper.assertNoStackTrace(responseBody);

        Map<String, Object> body = ApiResponseTestHelper.deserializeErrorBody(res);
        ApiResponseTestHelper.assertErrorFields(body);

        // Verify the sanitized message is present but stripped
        String msg = (String) body.get('message');
        System.assert(!msg.contains('SmokeTestOrchestrator'),
            'Internal class name must not appear in error message');
    }

    // =========================================================================
    // Success responses
    // =========================================================================

    @isTest
    static void testSuccess200WithAcknowledgmentPayload() {
        ApiResponseTestHelper.setUpRestContext();

        SmokeTestApiResponse.RunAcknowledgment payload =
            new SmokeTestApiResponse.RunAcknowledgment('a00000000000001AAA', 'in_progress');

        Test.startTest();
        SmokeTestApiResponse.success200().withBody(payload).send();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(200, res.statusCode, 'HTTP status should be 200');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals('a00000000000001AAA', body.get('executionId'),
            'executionId should match the provided value');
        System.assertEquals('in_progress', body.get('status'),
            'status should be in_progress');
        System.assert(body.containsKey('timestamp'),
            'timestamp field should be present in acknowledgment');
    }

    @isTest
    static void testSuccess200WithFullResultsPayload() {
        ApiResponseTestHelper.setUpRestContext();

        SmokeTestApiResponse.ScenarioResult scenario = new SmokeTestApiResponse.ScenarioResult();
        scenario.name       = 'AccountCrud';
        scenario.result     = 'pass';
        scenario.durationMs = 1200;
        scenario.errorDetail = null;

        SmokeTestApiResponse.MetadataIntegrity integrity = new SmokeTestApiResponse.MetadataIntegrity();
        integrity.status = 'pass';
        integrity.checks = new List<Object>();

        SmokeTestApiResponse.ExecutionResults results = new SmokeTestApiResponse.ExecutionResults();
        results.executionId         = 'a00000000000001AAA';
        results.status              = 'pass';
        results.scenarios           = new List<SmokeTestApiResponse.ScenarioResult>{ scenario };
        results.securityHealthScore = 87;
        results.metadataIntegrity   = integrity;
        results.executionDurationMs = 45000;
        results.timestamp           = '2026-08-12T14:35:00.000Z';

        Test.startTest();
        SmokeTestApiResponse.success200().withBody(results).send();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(200, res.statusCode, 'HTTP status should be 200');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals('pass', body.get('status'), 'status should be pass');
        System.assert(body.containsKey('scenarios'),     'scenarios array must be present');
        System.assert(body.containsKey('securityHealthScore'), 'securityHealthScore must be present');
        System.assert(body.containsKey('metadataIntegrity'),   'metadataIntegrity must be present');

        List<Object> scenarioList = (List<Object>) body.get('scenarios');
        System.assertEquals(1, scenarioList.size(), 'exactly one scenario should be present');
    }

    @isTest
    static void testSuccess201ForCreation() {
        ApiResponseTestHelper.setUpRestContext();

        Map<String, Object> payload = new Map<String, Object>{
            'executionId' => 'a00000000000002AAA',
            'status'      => 'queued'
        };

        Test.startTest();
        SmokeTestApiResponse.success201().withBody(payload).send();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(201, res.statusCode, 'HTTP status should be 201');
    }

    // =========================================================================
    // Headers
    // =========================================================================

    @isTest
    static void testXApiVersionHeaderOnAllResponses() {
        // Verify the X-API-Version header is present on both error and success responses

        ApiResponseTestHelper.setUpRestContext();
        SmokeTestApiResponse.error400()
            .withErrorCode('TEST').withMessage('test').send();
        String errorApiVersion = ApiResponseTestHelper.getResponseHeader(
            RestContext.response, 'X-API-Version');
        System.assertEquals('v1', errorApiVersion,
            'X-API-Version must be v1 on error responses');

        ApiResponseTestHelper.setUpRestContext();
        SmokeTestApiResponse.success200()
            .withBody(new Map<String, Object>{ 'ok' => true }).send();
        String successApiVersion = ApiResponseTestHelper.getResponseHeader(
            RestContext.response, 'X-API-Version');
        System.assertEquals('v1', successApiVersion,
            'X-API-Version must be v1 on success responses');
    }

    @isTest
    static void testContentTypeHeaderOnAllResponses() {
        ApiResponseTestHelper.setUpRestContext();
        SmokeTestApiResponse.error404()
            .withErrorCode('NOT_FOUND').withMessage('not found').send();

        String contentType = ApiResponseTestHelper.getResponseHeader(
            RestContext.response, 'Content-Type');
        System.assertEquals('application/json;charset=UTF-8', contentType,
            'Content-Type must always be application/json;charset=UTF-8');
    }

    // =========================================================================
    // Edge cases
    // =========================================================================

    @isTest
    static void testNullRestContextThrowsIllegalState() {
        RestContext.response = null;

        Test.startTest();
        SmokeTestApiResponse.IllegalStateException thrownEx = null;
        try {
            SmokeTestApiResponse.error500()
                .withErrorCode('TEST').withMessage('test').send();
        } catch (SmokeTestApiResponse.IllegalStateException ex) {
            thrownEx = ex;
        }
        Test.stopTest();

        System.assert(thrownEx != null,
            'send() must throw IllegalStateException when RestContext.response is null');
        System.assert(thrownEx.getMessage().contains('RestContext.response is null'),
            'Exception message should describe the missing context');
    }

    @isTest
    static void testLongMessageTruncation() {
        ApiResponseTestHelper.setUpRestContext();

        // Build a 6000-char message to trigger the 5000-char truncation
        String longMsg = 'A'.repeat(6000);

        Test.startTest();
        SmokeTestApiResponse.error400()
            .withErrorCode('LONG_MSG_TEST')
            .withMessage(longMsg)
            .send();
        Test.stopTest();

        RestResponse res = RestContext.response;
        Map<String, Object> body = ApiResponseTestHelper.deserializeErrorBody(res);
        String returnedMsg = (String) body.get('message');

        System.assert(returnedMsg.length() <= 5010,
            'Message should be truncated (5000 chars + [TRUNCATED] suffix)');
        System.assert(returnedMsg.endsWith('[TRUNCATED]'),
            'Truncated message must end with [TRUNCATED] suffix');
    }

    @isTest
    static void testNullErrorCodeDefaults() {
        ApiResponseTestHelper.setUpRestContext();

        Test.startTest();
        SmokeTestApiResponse.error400()
            .withErrorCode(null)
            .withMessage('Something went wrong')
            .send();
        Test.stopTest();

        RestResponse res = RestContext.response;
        Map<String, Object> body = ApiResponseTestHelper.deserializeErrorBody(res);
        System.assertEquals('UNKNOWN_ERROR', body.get('errorCode'),
            'null errorCode should default to UNKNOWN_ERROR');
    }

    @isTest
    static void testNullMessageDefaultsToGenericWithReferenceId() {
        ApiResponseTestHelper.setUpRestContext();

        Test.startTest();
        SmokeTestApiResponse.error500()
            .withErrorCode('INTERNAL_ERROR')
            .withMessage(null)
            .send();
        Test.stopTest();

        RestResponse res = RestContext.response;
        Map<String, Object> body = ApiResponseTestHelper.deserializeErrorBody(res);
        String msg = (String) body.get('message');
        System.assert(msg != null && msg.length() > 0,
            'null message should default to a non-empty generic message');
        String refId = (String) body.get('referenceId');
        System.assert(msg.contains(refId),
            'default message should include the referenceId for support correlation');
    }
}
