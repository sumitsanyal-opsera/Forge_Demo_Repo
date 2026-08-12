/**
 * Unit tests for CaseCreationScenario.
 * Coverage target: ≥90% on CaseCreationScenario.cls.
 */
@isTest
private class CaseCreationScenarioTest {

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
        ScenarioResult result = new CaseCreationScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(true, result.passed,
            'Case creation scenario must pass; error: ' + result.errorDetail);
        System.assertEquals(CaseCreationScenario.SCENARIO_NAME, result.scenarioName);
        System.assertEquals(null, result.errorType);
        System.assertNotEquals(null, result.durationMs);
    }

    // =========================================================================
    // Exception path coverage
    // =========================================================================

    @isTest
    static void testExecuteDmlException() {
        CaseCreationScenario.injectException = new DmlException('Simulated Case DML failure');
        try {
            ScenarioResult result = new CaseCreationScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('DML_EXCEPTION', result.errorType);
            System.assert(result.errorDetail.contains('Simulated Case DML failure'));
        } finally {
            CaseCreationScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteUnexpectedError() {
        CaseCreationScenario.injectException = new IllegalArgumentException('Unexpected case error');
        try {
            ScenarioResult result = new CaseCreationScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('UNEXPECTED_ERROR', result.errorType);
        } finally {
            CaseCreationScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteAssertionFailed() {
        CaseCreationScenario.triggerAssertFail = true;
        try {
            ScenarioResult result = new CaseCreationScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('ASSERTION_FAILED', result.errorType);
        } finally {
            CaseCreationScenario.triggerAssertFail = false;
        }
    }

    @isTest
    static void testErrorDetailTruncatedAt1000Chars() {
        CaseCreationScenario.injectException = new DmlException('X'.repeat(1500));
        try {
            ScenarioResult result = new CaseCreationScenario().execute(makeContext());
            System.assert(result.errorDetail.length() <= 1000,
                'errorDetail must be capped at 1000 characters');
        } finally {
            CaseCreationScenario.injectException = null;
        }
    }

    // =========================================================================
    // Metadata and budget
    // =========================================================================

    @isTest
    static void testGetMetadata() {
        ScenarioMetadata meta = new CaseCreationScenario().getMetadata();

        System.assertEquals('Case_Creation', meta.scenarioName);
        System.assertEquals(true, meta.isCritical);
        System.assertEquals('Service', meta.cloudType,
            'Case scenario must be Service cloud type');
        System.assertEquals(40, meta.executionOrder);
    }

    @isTest
    static void testGetGovernorBudget() {
        GovernorBudgetConfig budget = new CaseCreationScenario().getGovernorBudget();

        System.assertEquals(5000, budget.cpuBudgetMs);
        System.assertEquals(50,   budget.soqlBudget);
        System.assertEquals(50,   budget.dmlBudget);
    }

    @isTest
    static void testImplementsISmokeTestScenario() {
        ISmokeTestScenario scenario = new CaseCreationScenario();
        System.assertNotEquals(null, scenario.getMetadata());
        System.assertNotEquals(null, scenario.getGovernorBudget());
    }
}
