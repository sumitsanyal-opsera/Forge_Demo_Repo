/**
 * Unit tests for SecurityHealthCheckService.
 *
 * Test scenarios:
 *   Success full data       — HTTP 200 with score + 2 risk categories
 *   Success partial data    — HTTP 200 with score but null SecurityRiskCategory
 *   Empty result set        — HTTP 200 with zero records
 *   Malformed JSON          — HTTP 200 with non-parseable body
 *   Authentication failure  — HTTP 401
 *   Permission failure      — HTTP 403
 *   Server error            — HTTP 500
 *   Unexpected HTTP status  — HTTP 418
 *   API limit exhausted     — pre-flight guard returns SKIPPED
 *   Audit log creation      — DML handler captures records for success and error
 */
@isTest
private class SecurityHealthCheckServiceTest {

    // =========================================================================
    // Mock DML handler — captures calls, no database interaction
    // =========================================================================

    private class MockDmlHandler implements IDmlHandler {
        public List<SObject> insertedSingles = new List<SObject>();
        public List<SObject> insertedBulk    = new List<SObject>();

        public void insertRecord(SObject record) {
            insertedSingles.add(record);
        }

        public void insertRecords(List<SObject> records) {
            insertedBulk.addAll(records);
        }
    }

    // =========================================================================
    // Helper: build service with injected mock
    // =========================================================================

    private static SecurityHealthCheckService buildService(
        SecurityHealthCheckService.IHttpCallout http,
        MockDmlHandler dml
    ) {
        return new SecurityHealthCheckService(http, dml);
    }

    // =========================================================================
    // Success — full data
    // =========================================================================

    @isTest
    static void testCaptureScore_Success_FullData_ReturnsPassResult() {
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.PASS,
            result.thresholdStatus,
            'Full-data success should return PASS status'
        );
        Assert.areEqual(85, result.overallScore, 'Score should be 85');
        Assert.isNotNull(result.capturedAt, 'capturedAt must be populated');
        Assert.areEqual(2, result.riskCategories.size(), 'Should parse 2 risk categories');
        Assert.areEqual('PasswordPolicies', result.riskCategories[0].categoryName);
        Assert.areEqual(100, result.riskCategories[0].score);
        Assert.areEqual(2, result.riskCategories[0].settings.size(), 'Should parse 2 settings for PasswordPolicies');
        Assert.isFalse(result.remediationLinks.isEmpty(), 'Remediation links should be populated');
    }

    @isTest
    static void testCaptureScore_Success_RiskCategorySettings_Parsed() {
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        SecurityHealthCheckResult.SecuritySetting setting = result.riskCategories[0].settings[0];
        Assert.areEqual('MinimumPasswordLength', setting.settingName);
        Assert.areEqual('8', setting.value);
        Assert.areEqual('15', setting.recommendation);
    }

    // =========================================================================
    // Success — partial data (null SecurityRiskCategory)
    // =========================================================================

    @isTest
    static void testCaptureScore_PartialData_NullRiskCategories_ReturnsPassResult() {
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.partialData(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.PASS,
            result.thresholdStatus,
            'Null risk categories should still return PASS when score > 0'
        );
        Assert.areEqual(75, result.overallScore, 'Score should be 75');
        Assert.areEqual(
            0, result.riskCategories.size(),
            'Empty list returned when SecurityRiskCategory is null'
        );
    }

    // =========================================================================
    // Empty result set
    // =========================================================================

    @isTest
    static void testCaptureScore_EmptyResultSet_ReturnsErrorResult() {
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.emptyResult(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.ERROR,
            result.thresholdStatus,
            'Empty records array should return ERROR status'
        );
        Assert.areEqual(-1, result.overallScore, 'Score should be -1 for empty result');
        Assert.isNotNull(result.diagnosticMessage, 'Diagnostic message must be populated');
        Assert.isTrue(
            result.diagnosticMessage.containsIgnoreCase('No SecurityHealthCheck records'),
            'Diagnostic message should describe the empty result: ' + result.diagnosticMessage
        );
    }

    // =========================================================================
    // Malformed JSON
    // =========================================================================

    @isTest
    static void testCaptureScore_MalformedJson_ReturnsErrorResult() {
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.malformed(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.ERROR,
            result.thresholdStatus,
            'Malformed JSON should return ERROR status'
        );
        Assert.areEqual(-1, result.overallScore);
        Assert.isTrue(
            result.diagnosticMessage.containsIgnoreCase('Malformed') ||
            result.diagnosticMessage.containsIgnoreCase('parsing'),
            'Diagnostic should mention parse failure: ' + result.diagnosticMessage
        );
    }

    // =========================================================================
    // HTTP error responses
    // =========================================================================

    @isTest
    static void testCaptureScore_AuthFailure_ReturnsErrorResult() {
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.authFailure(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.ERROR,
            result.thresholdStatus,
            'HTTP 401 should return ERROR status'
        );
        Assert.areEqual(-1, result.overallScore);
        Assert.isTrue(
            result.diagnosticMessage.containsIgnoreCase('Authentication failed'),
            'Diagnostic should mention auth failure: ' + result.diagnosticMessage
        );
    }

    @isTest
    static void testCaptureScore_PermissionFailure_ReturnsErrorResult() {
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.permissionFailure(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.ERROR,
            result.thresholdStatus,
            'HTTP 403 should return ERROR status'
        );
        Assert.isTrue(
            result.diagnosticMessage.containsIgnoreCase('Insufficient permissions'),
            'Diagnostic should mention insufficient permissions: ' + result.diagnosticMessage
        );
    }

    @isTest
    static void testCaptureScore_ServerError_ReturnsErrorResult() {
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.serverError(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.ERROR,
            result.thresholdStatus,
            'HTTP 500 should return ERROR status'
        );
        Assert.isTrue(
            result.diagnosticMessage.containsIgnoreCase('server error'),
            'Diagnostic should mention server error: ' + result.diagnosticMessage
        );
    }

    @isTest
    static void testCaptureScore_UnexpectedHttpStatus_ReturnsErrorResult() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(418);
        res.setBody('I am a teapot');
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = new SecurityHealthCheckService(
            new FixedResponseCallout(res), dml
        );

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        Assert.areEqual(SecurityHealthCheckResult.ThresholdStatus.ERROR, result.thresholdStatus);
        Assert.isTrue(
            result.diagnosticMessage.contains('418'),
            'Diagnostic should include status code: ' + result.diagnosticMessage
        );
    }

    // =========================================================================
    // API limit exhaustion
    // =========================================================================

    @isTest
    static void testCaptureScore_ApiLimitExhausted_ReturnsSkippedResult() {
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);
        SecurityHealthCheckService.injectedApiCallsRemaining = 0;

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        SecurityHealthCheckService.injectedApiCallsRemaining = null;

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.SKIPPED,
            result.thresholdStatus,
            'Zero API calls remaining should return SKIPPED'
        );
        Assert.areEqual(-1, result.overallScore);
        Assert.isTrue(
            result.diagnosticMessage.containsIgnoreCase('API call limit'),
            'Diagnostic should mention API limit: ' + result.diagnosticMessage
        );
    }

    // =========================================================================
    // Audit log verification
    // =========================================================================

    @isTest
    static void testCaptureScore_AuditLogWritten_OnSuccess() {
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);

        Test.startTest();
        svc.captureScore();
        Test.stopTest();

        Assert.areEqual(1, dml.insertedBulk.size(), 'Exactly one audit log record should be written');
        SmokeTestAuditLog__c log = (SmokeTestAuditLog__c) dml.insertedBulk[0];
        Assert.areEqual(AuditLogEntry.ACTION_TEST_EXECUTION, log.ActionType__c);
        Assert.areEqual('SecurityHealthCheck', log.ResourceType__c);
        Assert.areEqual('PASS', log.Outcome__c);
    }

    @isTest
    static void testCaptureScore_AuditLogWritten_OnError() {
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.authFailure(), dml);

        Test.startTest();
        svc.captureScore();
        Test.stopTest();

        Assert.areEqual(1, dml.insertedBulk.size(), 'Audit log should be written on error');
        SmokeTestAuditLog__c log = (SmokeTestAuditLog__c) dml.insertedBulk[0];
        Assert.areEqual('ERROR', log.Outcome__c);
    }

    @isTest
    static void testCaptureScore_AuditLogWritten_OnSkipped() {
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);
        SecurityHealthCheckService.injectedApiCallsRemaining = 0;

        Test.startTest();
        svc.captureScore();
        Test.stopTest();

        SecurityHealthCheckService.injectedApiCallsRemaining = null;

        Assert.areEqual(1, dml.insertedBulk.size(), 'Audit log should be written on SKIPPED');
        SmokeTestAuditLog__c log = (SmokeTestAuditLog__c) dml.insertedBulk[0];
        Assert.areEqual('SKIPPED', log.Outcome__c);
    }

    // =========================================================================
    // Interface: SecurityHealthCheckResult factory methods
    // =========================================================================

    @isTest
    static void testResultFactory_Error_SetsFieldsCorrectly() {
        SecurityHealthCheckResult r = SecurityHealthCheckResult.error('test error');
        Assert.areEqual(SecurityHealthCheckResult.ThresholdStatus.ERROR, r.thresholdStatus);
        Assert.areEqual(-1, r.overallScore);
        Assert.areEqual('test error', r.diagnosticMessage);
        Assert.isNotNull(r.capturedAt);
        Assert.isNotNull(r.riskCategories);
        Assert.isNotNull(r.remediationLinks);
    }

    @isTest
    static void testResultFactory_Skipped_SetsFieldsCorrectly() {
        SecurityHealthCheckResult r = SecurityHealthCheckResult.skipped('budget exhausted');
        Assert.areEqual(SecurityHealthCheckResult.ThresholdStatus.SKIPPED, r.thresholdStatus);
        Assert.areEqual(-1, r.overallScore);
        Assert.areEqual('budget exhausted', r.diagnosticMessage);
    }

    // =========================================================================
    // Inner helper: fixed-response callout for ad-hoc status codes
    // =========================================================================

    private class FixedResponseCallout implements SecurityHealthCheckService.IHttpCallout {
        private final HttpResponse response;

        public FixedResponseCallout(HttpResponse response) {
            this.response = response;
        }

        public HttpResponse send(HttpRequest req) {
            return response;
        }
    }
}
