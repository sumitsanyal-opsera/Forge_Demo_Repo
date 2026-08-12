/**
 * Unit tests for OpportunityCrudScenario.
 * Coverage target: ≥90% on OpportunityCrudScenario.cls.
 */
@isTest
private class OpportunityCrudScenarioTest {

    private static SmokeTestContext makeContext() {
        SmokeTestExecution__c exec = new SmokeTestExecution__c();
        insert exec;
        return new SmokeTestContext(exec.Id, 'test-org', null);
    }

    // =========================================================================
    // Success path
    // =========================================================================

    @isTest
    static void testExecuteSuccess() {
        SmokeTestContext ctx = makeContext();
        Test.startTest();
        ScenarioResult result = new OpportunityCrudScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(true, result.passed,
            'Opportunity pipeline scenario must pass; error: ' + result.errorDetail);
        System.assertEquals(OpportunityCrudScenario.SCENARIO_NAME, result.scenarioName);
        System.assertEquals(null, result.errorType);
        System.assertNotEquals(null, result.durationMs);
    }

    // =========================================================================
    // Exception path coverage
    // =========================================================================

    @isTest
    static void testExecuteDmlException() {
        OpportunityCrudScenario.injectException = new DmlException('Simulated Opp DML failure');
        try {
            ScenarioResult result = new OpportunityCrudScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('DML_EXCEPTION', result.errorType);
        } finally {
            OpportunityCrudScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteUnexpectedError() {
        OpportunityCrudScenario.injectException = new IllegalArgumentException('Unexpected opp error');
        try {
            ScenarioResult result = new OpportunityCrudScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('UNEXPECTED_ERROR', result.errorType);
        } finally {
            OpportunityCrudScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteAssertionFailed() {
        OpportunityCrudScenario.triggerAssertFail = true;
        try {
            ScenarioResult result = new OpportunityCrudScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('ASSERTION_FAILED', result.errorType);
        } finally {
            OpportunityCrudScenario.triggerAssertFail = false;
        }
    }

    @isTest
    static void testErrorDetailTruncatedAt1000Chars() {
        OpportunityCrudScenario.injectException = new DmlException('O'.repeat(1500));
        try {
            ScenarioResult result = new OpportunityCrudScenario().execute(makeContext());
            System.assert(result.errorDetail.length() <= 1000,
                'errorDetail must be capped at 1000 characters');
        } finally {
            OpportunityCrudScenario.injectException = null;
        }
    }

    // =========================================================================
    // Metadata and budget
    // =========================================================================

    @isTest
    static void testGetMetadata() {
        ScenarioMetadata meta = new OpportunityCrudScenario().getMetadata();

        System.assertEquals('Opportunity_Pipeline', meta.scenarioName);
        System.assertEquals(true, meta.isCritical);
        System.assertEquals('Sales', meta.cloudType);
        System.assertEquals(30, meta.executionOrder);
    }

    @isTest
    static void testGetGovernorBudget() {
        GovernorBudgetConfig budget = new OpportunityCrudScenario().getGovernorBudget();

        System.assertEquals(5000, budget.cpuBudgetMs);
        System.assertEquals(50,   budget.soqlBudget);
        System.assertEquals(50,   budget.dmlBudget);
    }

    @isTest
    static void testImplementsISmokeTestScenario() {
        ISmokeTestScenario scenario = new OpportunityCrudScenario();
        System.assertNotEquals(null, scenario.getMetadata());
        System.assertNotEquals(null, scenario.getGovernorBudget());
    }
}
