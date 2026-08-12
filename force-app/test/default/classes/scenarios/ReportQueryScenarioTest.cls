/**
 * Unit tests for ReportQueryScenario.
 * Coverage target: ≥90% on ReportQueryScenario.cls.
 */
@isTest
private class ReportQueryScenarioTest {

    private static SmokeTestContext makeContext(Map<String, Object> params) {
        SmokeTestExecution__c exec = new SmokeTestExecution__c();
        insert exec;
        return new SmokeTestContext(exec.Id, 'test-org', params);
    }

    private static SmokeTestContext makeContextWithQuery(String soql) {
        return makeContext(new Map<String, Object>{ 'soqlQuery' => soql });
    }

    // =========================================================================
    // Success paths
    // =========================================================================

    @isTest
    static void testSuccess_ValidQueryWithResults() {
        // User SObject always has at least one record (the running user)
        SmokeTestContext ctx = makeContextWithQuery('SELECT Id FROM User LIMIT 1');

        Test.startTest();
        ScenarioResult result = new ReportQueryScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(true, result.passed,
            'Valid SOQL with results must produce a passing result; error: ' + result.errorDetail);
        System.assertEquals(ReportQueryScenario.SCENARIO_NAME, result.scenarioName);
        System.assertEquals(null, result.errorType);
        System.assertNotEquals(null, result.durationMs);
    }

    @isTest
    static void testSuccess_ZeroRowsIsValid() {
        // Query returns 0 rows — this is a valid success (validates query execution, not data)
        SmokeTestContext ctx = makeContextWithQuery(
            'SELECT Id FROM Account WHERE Name = \'NONEXISTENT_SMOKE_TEST_99999\' LIMIT 1'
        );

        Test.startTest();
        ScenarioResult result = new ReportQueryScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(true, result.passed,
            'Zero-row result must be treated as success — scenario validates execution, not data existence');
    }

    @isTest
    static void testSuccess_AggregateQuery() {
        Account acc = new Account(Name = 'SMOKE_TEST ReportQuery Test');
        insert acc;
        SmokeTestContext ctx = makeContextWithQuery('SELECT COUNT(Id) cnt FROM Account');

        Test.startTest();
        ScenarioResult result = new ReportQueryScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(true, result.passed,
            'Aggregate query must succeed; error: ' + result.errorDetail);
    }

    // =========================================================================
    // Query failure
    // =========================================================================

    @isTest
    static void testQueryError_InvalidSoql() {
        // Completely invalid SOQL syntax → QueryException at runtime
        SmokeTestContext ctx = makeContextWithQuery('SELECT FROM Account');

        Test.startTest();
        ScenarioResult result = new ReportQueryScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('QUERY_ERROR', result.errorType);
        System.assertNotEquals(null, result.errorDetail);
    }

    @isTest
    static void testQueryError_NonexistentField() {
        // References a field that does not exist
        SmokeTestContext ctx = makeContextWithQuery(
            'SELECT NonExistentField__xyz FROM Account LIMIT 1'
        );

        Test.startTest();
        ScenarioResult result = new ReportQueryScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('QUERY_ERROR', result.errorType);
    }

    // =========================================================================
    // Configuration error
    // =========================================================================

    @isTest
    static void testConfigurationError_NoSoqlQuery() {
        SmokeTestContext ctx = makeContext(null);
        Test.startTest();
        ScenarioResult result = new ReportQueryScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CONFIGURATION_ERROR', result.errorType);
        System.assert(result.errorDetail.contains('soqlQuery'));
    }

    @isTest
    static void testConfigurationError_BlankSoqlQuery() {
        SmokeTestContext ctx = makeContextWithQuery('   ');
        Test.startTest();
        ScenarioResult result = new ReportQueryScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CONFIGURATION_ERROR', result.errorType);
    }

    // =========================================================================
    // Exception path coverage
    // =========================================================================

    @isTest
    static void testExecuteQueryException_ViaInjection() {
        // Exercises the catch(QueryException) branch via injection.
        // System.LimitException cannot be instantiated in Apex (runtime-only), so
        // the GOVERNOR_LIMIT_EXCEEDED path is a production safety net without a
        // dedicated unit test — coverage from other tests remains above 90%.
        ReportQueryScenario.injectException = new QueryException('Injected query failure');
        try {
            ScenarioResult result = new ReportQueryScenario().execute(
                makeContextWithQuery('SELECT Id FROM Account')
            );
            System.assertEquals(false, result.passed);
            System.assertEquals('QUERY_ERROR', result.errorType);
            System.assert(result.errorDetail.contains('Injected query failure'));
        } finally {
            ReportQueryScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteUnexpectedError() {
        ReportQueryScenario.injectException = new IllegalArgumentException('Unexpected report error');
        try {
            ScenarioResult result = new ReportQueryScenario().execute(
                makeContextWithQuery('SELECT Id FROM Account')
            );
            System.assertEquals(false, result.passed);
            System.assertEquals('UNEXPECTED_ERROR', result.errorType);
        } finally {
            ReportQueryScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteAssertionFailed() {
        ReportQueryScenario.triggerAssertFail = true;
        try {
            ScenarioResult result = new ReportQueryScenario().execute(
                makeContextWithQuery('SELECT Id FROM Account')
            );
            System.assertEquals(false, result.passed);
            System.assertEquals('ASSERTION_FAILED', result.errorType);
        } finally {
            ReportQueryScenario.triggerAssertFail = false;
        }
    }

    @isTest
    static void testErrorDetailTruncatedAt1000Chars() {
        ReportQueryScenario.injectException = new IllegalArgumentException('R'.repeat(1500));
        try {
            ScenarioResult result = new ReportQueryScenario().execute(
                makeContextWithQuery('SELECT Id FROM Account')
            );
            System.assert(result.errorDetail.length() <= 1000,
                'errorDetail must be capped at 1000 characters');
        } finally {
            ReportQueryScenario.injectException = null;
        }
    }

    // =========================================================================
    // Metadata and budget
    // =========================================================================

    @isTest
    static void testGetMetadata() {
        ScenarioMetadata meta = new ReportQueryScenario().getMetadata();

        System.assertEquals('Report_Generation', meta.scenarioName);
        System.assertEquals(false, meta.isCritical);
        System.assertEquals('Reporting', meta.cloudType);
        System.assertEquals(80, meta.executionOrder);
    }

    @isTest
    static void testGetGovernorBudget() {
        GovernorBudgetConfig budget = new ReportQueryScenario().getGovernorBudget();

        System.assertEquals(5000, budget.cpuBudgetMs);
        System.assertEquals(50,   budget.soqlBudget);
        System.assertEquals(50,   budget.dmlBudget);
    }

    @isTest
    static void testImplementsISmokeTestScenario() {
        ISmokeTestScenario scenario = new ReportQueryScenario();
        System.assertNotEquals(null, scenario.getMetadata());
        System.assertNotEquals(null, scenario.getGovernorBudget());
    }
}
