/**
 * Unit tests for AccountCrudScenario.
 * Coverage target: ≥90% on AccountCrudScenario.cls.
 */
@isTest
private class AccountCrudScenarioTest {

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
        ScenarioResult result = new AccountCrudScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(true, result.passed,
            'Account CRUD must pass on a standard org; error: ' + result.errorDetail);
        System.assertEquals(AccountCrudScenario.SCENARIO_NAME, result.scenarioName);
        System.assertEquals(null, result.errorType);
        System.assertEquals(null, result.errorDetail);
        System.assertNotEquals(null, result.durationMs);
        System.assert(result.durationMs >= 0, 'durationMs must be non-negative');
    }

    // =========================================================================
    // Exception path coverage
    // =========================================================================

    @isTest
    static void testExecuteDmlException() {
        AccountCrudScenario.injectException = new DmlException('Simulated DML failure');
        try {
            ScenarioResult result = new AccountCrudScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('DML_EXCEPTION', result.errorType);
            System.assert(result.errorDetail.contains('Simulated DML failure'),
                'errorDetail must contain the exception message');
        } finally {
            AccountCrudScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteUnexpectedError() {
        AccountCrudScenario.injectException = new IllegalArgumentException('Unexpected problem');
        try {
            ScenarioResult result = new AccountCrudScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('UNEXPECTED_ERROR', result.errorType);
        } finally {
            AccountCrudScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteAssertionFailed() {
        AccountCrudScenario.triggerAssertFail = true;
        try {
            ScenarioResult result = new AccountCrudScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('ASSERTION_FAILED', result.errorType);
        } finally {
            AccountCrudScenario.triggerAssertFail = false;
        }
    }

    @isTest
    static void testErrorDetailTruncatedAt1000Chars() {
        AccountCrudScenario.injectException = new DmlException('E'.repeat(1500));
        try {
            ScenarioResult result = new AccountCrudScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assert(result.errorDetail.length() <= 1000,
                'errorDetail must be capped at 1000 characters');
        } finally {
            AccountCrudScenario.injectException = null;
        }
    }

    // =========================================================================
    // Metadata and budget
    // =========================================================================

    @isTest
    static void testGetMetadata() {
        ScenarioMetadata meta = new AccountCrudScenario().getMetadata();

        System.assertEquals('Account_CRUD', meta.scenarioName);
        System.assertEquals(true, meta.isCritical);
        System.assertEquals('Sales', meta.cloudType);
        System.assertEquals(10, meta.executionOrder);
        System.assertNotEquals(null, meta.description);
    }

    @isTest
    static void testGetGovernorBudget() {
        GovernorBudgetConfig budget = new AccountCrudScenario().getGovernorBudget();

        System.assertEquals(5000, budget.cpuBudgetMs);
        System.assertEquals(50,   budget.soqlBudget);
        System.assertEquals(50,   budget.dmlBudget);
        System.assertEquals(30,   budget.timeoutSeconds);
    }

    @isTest
    static void testImplementsISmokeTestScenario() {
        ISmokeTestScenario scenario = new AccountCrudScenario();
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
        new AccountCrudScenario().execute(ctx);
        Integer soqlDelta  = Limits.getQueries()        - soqlBefore;
        Integer dmlDelta   = Limits.getDmlStatements()  - dmlBefore;
        Integer cpuDelta   = Limits.getCpuTime()        - cpuBefore;
        Test.stopTest();

        System.assert(soqlDelta <= 50,
            'SOQL budget exceeded: AccountCrudScenario used ' + soqlDelta + ' of 50 allowed');
        System.assert(dmlDelta  <= 50,
            'DML budget exceeded: AccountCrudScenario used '  + dmlDelta  + ' of 50 allowed');
        System.assert(cpuDelta  <= 5000,
            'CPU budget exceeded: AccountCrudScenario used '  + cpuDelta  + 'ms of 5000ms allowed');
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
            ScenarioResult result = new AccountCrudScenario().execute(ctx);
            Test.stopTest();
            System.assertEquals(true, result.passed,
                'Account CRUD must pass under System Administrator profile; error: ' + result.errorDetail);
        }
    }

    @isTest
    static void testRunAsStandardUser() {
        User stdUser = SmokeTestDataFactory.createUserWithProfile('Standard User');
        SmokeTestContext ctx = makeContext();
        System.runAs(stdUser) {
            Test.startTest();
            ScenarioResult result = new AccountCrudScenario().execute(ctx);
            Test.stopTest();
            System.assertNotEquals(null, result,
                'AccountCrudScenario must return a structured result (not throw) under Standard User profile');
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
            ScenarioResult result = new AccountCrudScenario().execute(ctx);
            Test.stopTest();
            System.assertEquals(false, result.passed,
                'Account CRUD must fail gracefully for Minimum Access profile (no Account DML permission)');
            System.assertNotEquals(null, result.errorType,
                'errorType must identify the failure kind for Minimum Access profile execution');
        }
    }
}
