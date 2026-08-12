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
        new OpportunityCrudScenario().execute(ctx);
        Integer soqlDelta  = Limits.getQueries()        - soqlBefore;
        Integer dmlDelta   = Limits.getDmlStatements()  - dmlBefore;
        Integer cpuDelta   = Limits.getCpuTime()        - cpuBefore;
        Test.stopTest();

        System.assert(soqlDelta <= 50,
            'SOQL budget exceeded: OpportunityCrudScenario used ' + soqlDelta + ' of 50 allowed');
        System.assert(dmlDelta  <= 50,
            'DML budget exceeded: OpportunityCrudScenario used '  + dmlDelta  + ' of 50 allowed');
        System.assert(cpuDelta  <= 5000,
            'CPU budget exceeded: OpportunityCrudScenario used '  + cpuDelta  + 'ms of 5000ms allowed');
    }

    // =========================================================================
    // System.runAs() role-based execution
    // =========================================================================

    @isTest
    static void testRunAsSystemAdministrator() {
        User adminUser = SmokeTestDataFactory.createUserWithProfile('System Administrator');
        SmokeTestContext ctx = makeContext();
        System.runAs(adminUser) {
            Test.startTest();
            ScenarioResult result = new OpportunityCrudScenario().execute(ctx);
            Test.stopTest();
            System.assertEquals(true, result.passed,
                'Opportunity pipeline must pass under System Administrator profile; error: ' + result.errorDetail);
        }
    }

    @isTest
    static void testRunAsStandardUser() {
        User stdUser = SmokeTestDataFactory.createUserWithProfile('Standard User');
        SmokeTestContext ctx = makeContext();
        System.runAs(stdUser) {
            Test.startTest();
            ScenarioResult result = new OpportunityCrudScenario().execute(ctx);
            Test.stopTest();
            System.assertNotEquals(null, result,
                'OpportunityCrudScenario must return a structured result (not throw) under Standard User profile');
            System.assertNotEquals(null, result.durationMs,
                'durationMs must be populated for Standard User execution');
        }
    }

    @isTest
    static void testRunAsMinimumAccessProfile_FailsGracefully() {
        User minUser = SmokeTestDataFactory.createUserWithProfile('Minimum Access - Salesforce');
        SmokeTestContext ctx = makeContext();
        System.runAs(minUser) {
            Test.startTest();
            ScenarioResult result = new OpportunityCrudScenario().execute(ctx);
            Test.stopTest();
            System.assertEquals(false, result.passed,
                'Opportunity pipeline must fail gracefully for Minimum Access profile (no Opportunity DML permission)');
            System.assertNotEquals(null, result.errorType,
                'errorType must identify the failure kind for Minimum Access profile execution');
        }
    }
}
