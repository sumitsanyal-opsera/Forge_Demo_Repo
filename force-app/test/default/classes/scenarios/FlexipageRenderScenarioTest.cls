/**
 * Unit tests for FlexipageRenderScenario.
 * Coverage target: ≥90% on FlexipageRenderScenario.cls.
 *
 * All Tooling API HTTP calls are intercepted by MockHttpCallout.
 * The tests below cover the full decision tree:
 *   success → FLEXIPAGE_NOT_FOUND → FLEXIPAGE_MISCONFIGURED →
 *   TOOLING_API_ERROR (non-2xx) → TOOLING_API_ERROR (CalloutException) →
 *   PARSE_ERROR → CONFIGURATION_ERROR (missing/invalid name) →
 *   exception injection paths.
 */
@isTest
private class FlexipageRenderScenarioTest {

    private static final String FOUND_BODY =
        '{"totalSize":1,"done":true,"records":[{"attributes":{"type":"FlexiPage"},' +
        '"Id":"0M0000000001AAA","DeveloperName":"Account_Record_Page","MasterLabel":"Account Record Page"}]}';

    private static final String NOT_FOUND_BODY =
        '{"totalSize":0,"done":true,"records":[]}';

    private static final String MISCONFIGURED_BODY =
        '{"totalSize":1,"done":true,"records":[]}';

    private static SmokeTestContext makeContext(Map<String, Object> params) {
        SmokeTestExecution__c exec = new SmokeTestExecution__c();
        insert exec;
        return new SmokeTestContext(exec.Id, 'test-org', params);
    }

    private static SmokeTestContext makeContextWithPage(String devName) {
        return makeContext(new Map<String, Object>{ 'flexipageDevName' => devName });
    }

    // =========================================================================
    // Success — Tooling API returns a FlexiPage record
    // =========================================================================

    @isTest
    static void testSuccess_FlexipageFound() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, FOUND_BODY));
        SmokeTestContext ctx = makeContextWithPage('Account_Record_Page');

        Test.startTest();
        ScenarioResult result = new FlexipageRenderScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(true, result.passed,
            'FlexiPage found must produce a passing result; error: ' + result.errorDetail);
        System.assertEquals(FlexipageRenderScenario.SCENARIO_NAME, result.scenarioName);
        System.assertEquals(null, result.errorType);
        System.assertNotEquals(null, result.durationMs);
    }

    // =========================================================================
    // FLEXIPAGE_NOT_FOUND — Tooling API returns totalSize=0
    // =========================================================================

    @isTest
    static void testFlexipageNotFound() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, NOT_FOUND_BODY));
        SmokeTestContext ctx = makeContextWithPage('Missing_Page');

        Test.startTest();
        ScenarioResult result = new FlexipageRenderScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('FLEXIPAGE_NOT_FOUND', result.errorType);
        System.assert(result.errorDetail.contains('Missing_Page'),
            'Error detail must include the queried DeveloperName');
    }

    // =========================================================================
    // FLEXIPAGE_MISCONFIGURED — totalSize>0 but records array is empty
    // =========================================================================

    @isTest
    static void testFlexipageMisconfigured() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, MISCONFIGURED_BODY));
        SmokeTestContext ctx = makeContextWithPage('Corrupt_Page');

        Test.startTest();
        ScenarioResult result = new FlexipageRenderScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('FLEXIPAGE_MISCONFIGURED', result.errorType);
        System.assert(result.errorDetail.contains('Corrupt_Page'));
    }

    // =========================================================================
    // TOOLING_API_ERROR — non-2xx HTTP response
    // =========================================================================

    @isTest
    static void testToolingApiError_500() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(500, 'Internal Server Error'));
        SmokeTestContext ctx = makeContextWithPage('Account_Record_Page');

        Test.startTest();
        ScenarioResult result = new FlexipageRenderScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('TOOLING_API_ERROR', result.errorType);
        System.assert(result.errorDetail.contains('500'));
    }

    @isTest
    static void testToolingApiError_401_Unauthorized() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(401, 'Unauthorized'));
        SmokeTestContext ctx = makeContextWithPage('Account_Record_Page');

        Test.startTest();
        ScenarioResult result = new FlexipageRenderScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('TOOLING_API_ERROR', result.errorType);
    }

    // =========================================================================
    // TOOLING_API_ERROR — CalloutException (network/timeout failure)
    // =========================================================================

    @isTest
    static void testToolingApiError_CalloutException() {
        Test.setMock(HttpCalloutMock.class, MockHttpCallout.throwingCallout('Connection refused'));
        SmokeTestContext ctx = makeContextWithPage('Account_Record_Page');

        Test.startTest();
        ScenarioResult result = new FlexipageRenderScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('TOOLING_API_ERROR', result.errorType);
        System.assert(result.errorDetail.contains('Connection refused'));
    }

    // =========================================================================
    // PARSE_ERROR — malformed JSON response
    // =========================================================================

    @isTest
    static void testParseError_MalformedJson() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, 'NOT_VALID_JSON{{{'));
        SmokeTestContext ctx = makeContextWithPage('Account_Record_Page');

        Test.startTest();
        ScenarioResult result = new FlexipageRenderScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('PARSE_ERROR', result.errorType);
    }

    // =========================================================================
    // Configuration errors
    // =========================================================================

    @isTest
    static void testConfigurationError_NoPageName() {
        SmokeTestContext ctx = makeContext(null);
        Test.startTest();
        ScenarioResult result = new FlexipageRenderScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CONFIGURATION_ERROR', result.errorType);
        System.assert(result.errorDetail.contains('flexipageDevName'));
    }

    @isTest
    static void testConfigurationError_InvalidApiName() {
        // Contains spaces / special chars — not a valid DeveloperName
        SmokeTestContext ctx = makeContextWithPage('Invalid Page Name!');
        Test.startTest();
        ScenarioResult result = new FlexipageRenderScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CONFIGURATION_ERROR', result.errorType);
        System.assert(result.errorDetail.contains('Invalid Page Name!'));
    }

    // =========================================================================
    // Exception path coverage
    // =========================================================================

    @isTest
    static void testExecuteUnexpectedError() {
        FlexipageRenderScenario.injectException = new IllegalArgumentException('Unexpected error');
        try {
            ScenarioResult result = new FlexipageRenderScenario().execute(makeContextWithPage('SomePage'));
            System.assertEquals(false, result.passed);
            System.assertEquals('UNEXPECTED_ERROR', result.errorType);
        } finally {
            FlexipageRenderScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteAssertionFailed() {
        FlexipageRenderScenario.triggerAssertFail = true;
        try {
            ScenarioResult result = new FlexipageRenderScenario().execute(makeContextWithPage('SomePage'));
            System.assertEquals(false, result.passed);
            System.assertEquals('ASSERTION_FAILED', result.errorType);
        } finally {
            FlexipageRenderScenario.triggerAssertFail = false;
        }
    }

    @isTest
    static void testErrorDetailTruncatedAt1000Chars() {
        FlexipageRenderScenario.injectException = new IllegalArgumentException('X'.repeat(1500));
        try {
            ScenarioResult result = new FlexipageRenderScenario().execute(makeContextWithPage('SomePage'));
            System.assert(result.errorDetail.length() <= 1000,
                'errorDetail must be capped at 1000 characters');
        } finally {
            FlexipageRenderScenario.injectException = null;
        }
    }

    // =========================================================================
    // Metadata and budget
    // =========================================================================

    @isTest
    static void testGetMetadata() {
        ScenarioMetadata meta = new FlexipageRenderScenario().getMetadata();

        System.assertEquals('PageLayout_Render', meta.scenarioName);
        System.assertEquals(false, meta.isCritical);
        System.assertEquals('Platform', meta.cloudType);
        System.assertEquals(90, meta.executionOrder);
    }

    @isTest
    static void testGetGovernorBudget() {
        GovernorBudgetConfig budget = new FlexipageRenderScenario().getGovernorBudget();

        System.assertEquals(5000, budget.cpuBudgetMs);
        System.assertEquals(50,   budget.soqlBudget);
        System.assertEquals(50,   budget.dmlBudget);
    }

    @isTest
    static void testImplementsISmokeTestScenario() {
        ISmokeTestScenario scenario = new FlexipageRenderScenario();
        System.assertNotEquals(null, scenario.getMetadata());
        System.assertNotEquals(null, scenario.getGovernorBudget());
    }

    // =========================================================================
    // Governor limit budget compliance
    // =========================================================================

    @isTest
    static void testGovernorLimitBudget() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, FOUND_BODY));
        SmokeTestContext ctx = makeContextWithPage('Account_Record_Page');
        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        Integer dmlBefore  = Limits.getDmlStatements();
        Integer cpuBefore  = Limits.getCpuTime();
        new FlexipageRenderScenario().execute(ctx);
        Integer soqlDelta  = Limits.getQueries()        - soqlBefore;
        Integer dmlDelta   = Limits.getDmlStatements()  - dmlBefore;
        Integer cpuDelta   = Limits.getCpuTime()        - cpuBefore;
        Test.stopTest();

        System.assert(soqlDelta <= 50,
            'SOQL budget exceeded: FlexipageRenderScenario used ' + soqlDelta + ' of 50 allowed');
        System.assert(dmlDelta  <= 50,
            'DML budget exceeded: FlexipageRenderScenario used '  + dmlDelta  + ' of 50 allowed');
        System.assert(cpuDelta  <= 5000,
            'CPU budget exceeded: FlexipageRenderScenario used '  + cpuDelta  + 'ms of 5000ms allowed');
    }
}
