/**
 * Unit tests for SecurityHealthCheckService.
 *
 * Test scenarios:
 *   Success full data          — HTTP 200 with score + 2 risk categories
 *   Success partial data       — HTTP 200 with score but null SecurityRiskCategory
 *   Empty result set           — HTTP 200 with zero records
 *   Malformed JSON             — HTTP 200 with non-parseable body
 *   Authentication failure     — HTTP 401
 *   Permission failure         — HTTP 403
 *   Server error               — HTTP 500
 *   Unexpected HTTP status     — HTTP 418
 *   Network failure            — CalloutException
 *   API limit < 5              — pre-flight guard returns SKIPPED
 *   API limit exactly 5        — callout proceeds normally
 *   Cache hit (fresh)          — returns cached result without callout
 *   Cache expired              — fresh callout made when TTL exceeded
 *   Audit log creation         — DML handler captures records for success and error
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
    // Helpers
    // =========================================================================

    private static SecurityHealthCheckService buildService(
        SecurityHealthCheckService.IHttpCallout http,
        MockDmlHandler dml
    ) {
        return new SecurityHealthCheckService(http, dml);
    }

    private static void enableStaticCacheOnly() {
        SecurityHealthCheckCache.bypassPlatformCache = true;
        SecurityHealthCheckCache.staticCache.clear();
    }

    private static void resetCacheState() {
        SecurityHealthCheckCache.bypassPlatformCache = false;
        SecurityHealthCheckCache.staticCache.clear();
    }

    // =========================================================================
    // Success — full data
    // =========================================================================

    @isTest
    static void testCaptureScore_Success_FullData_ReturnsPassResult() {
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        resetCacheState();

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
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        resetCacheState();

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
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.partialData(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        resetCacheState();

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
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.emptyResult(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        resetCacheState();

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
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.malformed(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        resetCacheState();

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
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckDegradation.http401(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        resetCacheState();

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
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckDegradation.http403(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        resetCacheState();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.ERROR,
            result.thresholdStatus,
            'HTTP 403 should return ERROR status'
        );
        Assert.isTrue(
            result.diagnosticMessage.containsIgnoreCase('View Setup and Configuration'),
            'Diagnostic should mention the required permission: ' + result.diagnosticMessage
        );
        Assert.isTrue(
            result.diagnosticMessage.containsIgnoreCase('integration user'),
            'Diagnostic should mention the integration user: ' + result.diagnosticMessage
        );
    }

    @isTest
    static void testCaptureScore_ServerError_ReturnsErrorResult() {
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckDegradation.http500(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        resetCacheState();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.ERROR,
            result.thresholdStatus,
            'HTTP 500 should return ERROR status'
        );
        Assert.isTrue(
            result.diagnosticMessage.containsIgnoreCase('Unable to retrieve security health score'),
            'Diagnostic should contain the AC1 message prefix: ' + result.diagnosticMessage
        );
        Assert.isTrue(
            result.diagnosticMessage.contains('500'),
            'Diagnostic should include HTTP status code 500: ' + result.diagnosticMessage
        );
    }

    @isTest
    static void testCaptureScore_UnexpectedHttpStatus_ReturnsErrorResult() {
        enableStaticCacheOnly();
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

        resetCacheState();

        Assert.areEqual(SecurityHealthCheckResult.ThresholdStatus.ERROR, result.thresholdStatus);
        Assert.isTrue(
            result.diagnosticMessage.contains('418'),
            'Diagnostic should include status code: ' + result.diagnosticMessage
        );
    }

    // =========================================================================
    // Network failure (CalloutException)
    // =========================================================================

    @isTest
    static void testCaptureScore_NetworkError_ReturnsErrorResult() {
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckDegradation.networkError(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        resetCacheState();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.ERROR,
            result.thresholdStatus,
            'CalloutException should return ERROR status'
        );
        Assert.areEqual(-1, result.overallScore);
        Assert.isTrue(
            result.diagnosticMessage.containsIgnoreCase('Network error connecting to Tooling API'),
            'Diagnostic should mention network error: ' + result.diagnosticMessage
        );
    }

    // =========================================================================
    // API limit checks
    // =========================================================================

    @isTest
    static void testCaptureScore_ApiLimitBelowMinimum_ReturnsSkippedResult() {
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);
        SecurityHealthCheckService.injectedApiCallsRemaining = 4; // < 5

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        SecurityHealthCheckService.injectedApiCallsRemaining = null;
        resetCacheState();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.SKIPPED,
            result.thresholdStatus,
            'Fewer than 5 API calls remaining should return SKIPPED'
        );
        Assert.areEqual(-1, result.overallScore);
        Assert.isTrue(
            result.diagnosticMessage.containsIgnoreCase('API call limit approaching'),
            'Diagnostic should mention API limit approaching: ' + result.diagnosticMessage
        );
        Assert.isTrue(
            result.diagnosticMessage.containsIgnoreCase('security check skipped'),
            'Diagnostic should mention security check skipped: ' + result.diagnosticMessage
        );
    }

    @isTest
    static void testCaptureScore_ApiLimitAtMinimum_ProceedsWithCallout() {
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);
        SecurityHealthCheckService.injectedApiCallsRemaining = 5; // exactly 5 — callout proceeds

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        SecurityHealthCheckService.injectedApiCallsRemaining = null;
        resetCacheState();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.PASS,
            result.thresholdStatus,
            'Exactly 5 API calls remaining is NOT below minimum — callout should proceed'
        );
        Assert.areEqual(85, result.overallScore, 'Normal callout should return score 85');
    }

    // =========================================================================
    // Cache behaviour
    // =========================================================================

    @isTest
    static void testCaptureScore_CacheHit_ReturnsCachedResultWithoutCallout() {
        enableStaticCacheOnly();

        // Pre-populate the static cache with a 60-second entry
        String orgId = UserInfo.getOrganizationId();
        SecurityHealthCheckResult cachedResult = SecurityHealthCheckResult.error('from-cache-sentinel');
        SecurityHealthCheckCache.put(orgId, cachedResult, 60);

        // The mock would return a different (PASS) result — if the cache is used,
        // we should get the sentinel back, not the mock result.
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        resetCacheState();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.ERROR,
            result.thresholdStatus,
            'Cache hit should return the cached ERROR sentinel, not the mock PASS result'
        );
        Assert.areEqual(
            'from-cache-sentinel', result.diagnosticMessage,
            'Returned result should be the exact cached sentinel'
        );
    }

    @isTest
    static void testCaptureScore_CacheExpired_MakesFreshCallout() {
        enableStaticCacheOnly();

        // Pre-populate with an immediately-expiring entry (TTL = -1 sec → already expired)
        String orgId = UserInfo.getOrganizationId();
        SecurityHealthCheckResult staleResult = SecurityHealthCheckResult.error('stale-sentinel');
        SecurityHealthCheckCache.put(orgId, staleResult, -1);

        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);

        Test.startTest();
        SecurityHealthCheckResult result = svc.captureScore();
        Test.stopTest();

        resetCacheState();

        Assert.areEqual(
            SecurityHealthCheckResult.ThresholdStatus.PASS,
            result.thresholdStatus,
            'Expired cache entry should trigger a fresh callout returning PASS'
        );
        Assert.areEqual(85, result.overallScore,
            'Fresh callout should return score 85 from the success mock');
    }

    // =========================================================================
    // Audit log verification
    // =========================================================================

    @isTest
    static void testCaptureScore_AuditLogWritten_OnSuccess() {
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);

        Test.startTest();
        svc.captureScore();
        Test.stopTest();

        resetCacheState();

        Assert.areEqual(1, dml.insertedBulk.size(), 'Exactly one audit log record should be written');
        SmokeTestAuditLog__c log = (SmokeTestAuditLog__c) dml.insertedBulk[0];
        Assert.areEqual(AuditLogEntry.ACTION_TEST_EXECUTION, log.ActionType__c);
        Assert.areEqual('SecurityHealthCheck', log.ResourceType__c);
        Assert.areEqual('PASS', log.Outcome__c);
    }

    @isTest
    static void testCaptureScore_AuditLogWritten_OnError() {
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckDegradation.http401(), dml);

        Test.startTest();
        svc.captureScore();
        Test.stopTest();

        resetCacheState();

        Assert.areEqual(1, dml.insertedBulk.size(), 'Audit log should be written on error');
        SmokeTestAuditLog__c log = (SmokeTestAuditLog__c) dml.insertedBulk[0];
        Assert.areEqual('ERROR', log.Outcome__c);
    }

    @isTest
    static void testCaptureScore_AuditLogWritten_OnSkipped() {
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckResponse.success(), dml);
        SecurityHealthCheckService.injectedApiCallsRemaining = 4;

        Test.startTest();
        svc.captureScore();
        Test.stopTest();

        SecurityHealthCheckService.injectedApiCallsRemaining = null;
        resetCacheState();

        Assert.areEqual(1, dml.insertedBulk.size(), 'Audit log should be written on SKIPPED');
        SmokeTestAuditLog__c log = (SmokeTestAuditLog__c) dml.insertedBulk[0];
        Assert.areEqual('SKIPPED', log.Outcome__c);
    }

    @isTest
    static void testCaptureScore_AuditLogWritten_OnNetworkError() {
        enableStaticCacheOnly();
        MockDmlHandler dml = new MockDmlHandler();
        SecurityHealthCheckService svc = buildService(MockSecurityHealthCheckDegradation.networkError(), dml);

        Test.startTest();
        svc.captureScore();
        Test.stopTest();

        resetCacheState();

        Assert.areEqual(1, dml.insertedBulk.size(), 'Audit log should be written on network error');
        SmokeTestAuditLog__c log = (SmokeTestAuditLog__c) dml.insertedBulk[0];
        Assert.areEqual('ERROR', log.Outcome__c);
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
