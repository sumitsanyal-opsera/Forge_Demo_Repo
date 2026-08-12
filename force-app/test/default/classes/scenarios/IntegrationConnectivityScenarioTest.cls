/**
 * Unit tests for IntegrationConnectivityScenario.
 * Coverage target: ≥90% on IntegrationConnectivityScenario.cls.
 */
@isTest
private class IntegrationConnectivityScenarioTest {

    private static SmokeTestContext makeContext(Map<String, Object> params) {
        SmokeTestExecution__c exec = new SmokeTestExecution__c();
        insert exec;
        return new SmokeTestContext(exec.Id, 'test-org', params);
    }

    private static SmokeTestContext makeContextWithUrl(String url) {
        return makeContext(new Map<String, Object>{ 'endpointUrl' => url });
    }

    // =========================================================================
    // Success — 200 response
    // =========================================================================

    @isTest
    static void testSuccess_200Response() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"status":"ok"}'));
        SmokeTestContext ctx = makeContextWithUrl('https://api.example.com/health');

        Test.startTest();
        ScenarioResult result = new IntegrationConnectivityScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(true, result.passed,
            'HTTP 200 must produce a passing result; error: ' + result.errorDetail);
        System.assertEquals(IntegrationConnectivityScenario.SCENARIO_NAME, result.scenarioName);
        System.assertEquals(null, result.errorType);
        System.assertNotEquals(null, result.durationMs);
    }

    @isTest
    static void testSuccess_201Response() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(201, ''));
        SmokeTestContext ctx = makeContextWithUrl('https://api.example.com/resource');

        Test.startTest();
        ScenarioResult result = new IntegrationConnectivityScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(true, result.passed,
            'HTTP 201 (2xx) must produce a passing result');
    }

    // =========================================================================
    // Named Credential support
    // =========================================================================

    @isTest
    static void testSuccess_NamedCredential() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{}'));
        SmokeTestContext ctx = makeContext(new Map<String, Object>{
            'namedCredential' => 'SmokeTest_Integration'
        });

        Test.startTest();
        ScenarioResult result = new IntegrationConnectivityScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(true, result.passed,
            'Named Credential endpoint (callout:...) must resolve and succeed');
    }

    // =========================================================================
    // Endpoint error — non-2xx response
    // =========================================================================

    @isTest
    static void testEndpointError_500() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(500, 'Internal Server Error'));
        SmokeTestContext ctx = makeContextWithUrl('https://api.example.com/health');

        Test.startTest();
        ScenarioResult result = new IntegrationConnectivityScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('ENDPOINT_ERROR', result.errorType);
        System.assert(result.errorDetail.contains('500'),
            'Error detail must include the HTTP status code');
    }

    @isTest
    static void testEndpointError_404() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(404, 'Not Found'));
        SmokeTestContext ctx = makeContextWithUrl('https://api.example.com/missing');

        Test.startTest();
        ScenarioResult result = new IntegrationConnectivityScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('ENDPOINT_ERROR', result.errorType);
    }

    // =========================================================================
    // Callout exception (timeout / network failure)
    // =========================================================================

    @isTest
    static void testCalloutException_Timeout() {
        Test.setMock(HttpCalloutMock.class, MockHttpCallout.throwingCallout('Read timeout after 10000ms'));
        SmokeTestContext ctx = makeContextWithUrl('https://api.example.com/slow');

        Test.startTest();
        ScenarioResult result = new IntegrationConnectivityScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CALLOUT_EXCEPTION', result.errorType);
        System.assert(result.errorDetail.contains('Read timeout'));
    }

    // =========================================================================
    // Configuration errors
    // =========================================================================

    @isTest
    static void testConfigurationError_NoEndpoint() {
        SmokeTestContext ctx = makeContext(null);
        Test.startTest();
        ScenarioResult result = new IntegrationConnectivityScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CONFIGURATION_ERROR', result.errorType);
    }

    @isTest
    static void testConfigurationError_BlankEndpoint() {
        SmokeTestContext ctx = makeContext(new Map<String, Object>{ 'endpointUrl' => '   ' });
        Test.startTest();
        ScenarioResult result = new IntegrationConnectivityScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CONFIGURATION_ERROR', result.errorType);
    }

    // =========================================================================
    // Exception path coverage
    // =========================================================================

    @isTest
    static void testExecuteUnexpectedError() {
        IntegrationConnectivityScenario.injectException = new IllegalArgumentException('Unexpected error');
        try {
            ScenarioResult result = new IntegrationConnectivityScenario().execute(makeContextWithUrl('https://api.example.com'));
            System.assertEquals(false, result.passed);
            System.assertEquals('UNEXPECTED_ERROR', result.errorType);
        } finally {
            IntegrationConnectivityScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteAssertionFailed() {
        IntegrationConnectivityScenario.triggerAssertFail = true;
        try {
            ScenarioResult result = new IntegrationConnectivityScenario().execute(makeContextWithUrl('https://api.example.com'));
            System.assertEquals(false, result.passed);
            System.assertEquals('ASSERTION_FAILED', result.errorType);
        } finally {
            IntegrationConnectivityScenario.triggerAssertFail = false;
        }
    }

    @isTest
    static void testErrorDetailTruncatedAt1000Chars() {
        IntegrationConnectivityScenario.injectException = new IllegalArgumentException('E'.repeat(1500));
        try {
            ScenarioResult result = new IntegrationConnectivityScenario().execute(makeContextWithUrl('https://api.example.com'));
            System.assert(result.errorDetail.length() <= 1000,
                'errorDetail must be capped at 1000 characters');
        } finally {
            IntegrationConnectivityScenario.injectException = null;
        }
    }

    // =========================================================================
    // Metadata and budget
    // =========================================================================

    @isTest
    static void testGetMetadata() {
        ScenarioMetadata meta = new IntegrationConnectivityScenario().getMetadata();

        System.assertEquals('Integration_Callout', meta.scenarioName);
        System.assertEquals(true, meta.isCritical);
        System.assertEquals('Integration', meta.cloudType);
        System.assertEquals(100, meta.executionOrder);
    }

    @isTest
    static void testGetGovernorBudget() {
        GovernorBudgetConfig budget = new IntegrationConnectivityScenario().getGovernorBudget();

        System.assertEquals(5000, budget.cpuBudgetMs);
        System.assertEquals(50,   budget.soqlBudget);
        System.assertEquals(50,   budget.dmlBudget);
    }

    @isTest
    static void testImplementsISmokeTestScenario() {
        ISmokeTestScenario scenario = new IntegrationConnectivityScenario();
        System.assertNotEquals(null, scenario.getMetadata());
        System.assertNotEquals(null, scenario.getGovernorBudget());
    }
}
