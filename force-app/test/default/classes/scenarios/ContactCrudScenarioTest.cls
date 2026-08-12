/**
 * Unit tests for ContactCrudScenario.
 * Coverage target: ≥90% on ContactCrudScenario.cls.
 */
@isTest
private class ContactCrudScenarioTest {

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
        ScenarioResult result = new ContactCrudScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(true, result.passed,
            'Contact CRUD must pass on a standard org; error: ' + result.errorDetail);
        System.assertEquals(ContactCrudScenario.SCENARIO_NAME, result.scenarioName);
        System.assertEquals(null, result.errorType);
        System.assertNotEquals(null, result.durationMs);
    }

    // =========================================================================
    // Exception path coverage
    // =========================================================================

    @isTest
    static void testExecuteDmlException() {
        ContactCrudScenario.injectException = new DmlException('Simulated Contact DML failure');
        try {
            ScenarioResult result = new ContactCrudScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('DML_EXCEPTION', result.errorType);
            System.assert(result.errorDetail.contains('Simulated Contact DML failure'));
        } finally {
            ContactCrudScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteUnexpectedError() {
        ContactCrudScenario.injectException = new IllegalArgumentException('Unexpected contact error');
        try {
            ScenarioResult result = new ContactCrudScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('UNEXPECTED_ERROR', result.errorType);
        } finally {
            ContactCrudScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteAssertionFailed() {
        ContactCrudScenario.triggerAssertFail = true;
        try {
            ScenarioResult result = new ContactCrudScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('ASSERTION_FAILED', result.errorType);
        } finally {
            ContactCrudScenario.triggerAssertFail = false;
        }
    }

    @isTest
    static void testErrorDetailTruncatedAt1000Chars() {
        ContactCrudScenario.injectException = new DmlException('C'.repeat(1500));
        try {
            ScenarioResult result = new ContactCrudScenario().execute(makeContext());
            System.assert(result.errorDetail.length() <= 1000,
                'errorDetail must be capped at 1000 characters');
        } finally {
            ContactCrudScenario.injectException = null;
        }
    }

    // =========================================================================
    // Metadata and budget
    // =========================================================================

    @isTest
    static void testGetMetadata() {
        ScenarioMetadata meta = new ContactCrudScenario().getMetadata();

        System.assertEquals('Contact_CRUD', meta.scenarioName);
        System.assertEquals(true, meta.isCritical);
        System.assertEquals('Sales', meta.cloudType);
        System.assertEquals(20, meta.executionOrder);
    }

    @isTest
    static void testGetGovernorBudget() {
        GovernorBudgetConfig budget = new ContactCrudScenario().getGovernorBudget();

        System.assertEquals(5000, budget.cpuBudgetMs);
        System.assertEquals(50,   budget.soqlBudget);
        System.assertEquals(50,   budget.dmlBudget);
    }

    @isTest
    static void testImplementsISmokeTestScenario() {
        ISmokeTestScenario scenario = new ContactCrudScenario();
        System.assertNotEquals(null, scenario.getMetadata());
        System.assertNotEquals(null, scenario.getGovernorBudget());
    }

    // =========================================================================
    // Governor limit budget compliance
    // =========================================================================

    @isTest
    static void testGovernorLimitBudget() {
        SmokeTestContext ctx = makeContext();
        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        Integer dmlBefore  = Limits.getDmlStatements();
        Integer cpuBefore  = Limits.getCpuTime();
        new ContactCrudScenario().execute(ctx);
        Integer soqlDelta  = Limits.getQueries()        - soqlBefore;
        Integer dmlDelta   = Limits.getDmlStatements()  - dmlBefore;
        Integer cpuDelta   = Limits.getCpuTime()        - cpuBefore;
        Test.stopTest();

        System.assert(soqlDelta <= 50,
            'SOQL budget exceeded: ContactCrudScenario used ' + soqlDelta + ' of 50 allowed');
        System.assert(dmlDelta  <= 50,
            'DML budget exceeded: ContactCrudScenario used '  + dmlDelta  + ' of 50 allowed');
        System.assert(cpuDelta  <= 5000,
            'CPU budget exceeded: ContactCrudScenario used '  + cpuDelta  + 'ms of 5000ms allowed');
    }
}
