/**
 * Unit tests for AutomationTriggerScenario.
 * Coverage target: ≥90% on AutomationTriggerScenario.cls.
 *
 * The injectTriggerFieldValue static field bypasses the real dynamic SOQL query,
 * allowing simulation of "automation fired" and "automation not fired" outcomes
 * without requiring org-specific triggers or Process Builders in the test environment.
 * The real dynamic SOQL path is exercised via testAutomationNotFired_RealQuery.
 */
@isTest
private class AutomationTriggerScenarioTest {

    private static SmokeTestContext makeContext(Map<String, Object> params) {
        SmokeTestExecution__c exec = new SmokeTestExecution__c();
        insert exec;
        return new SmokeTestContext(exec.Id, 'test-org', params);
    }

    // =========================================================================
    // Success — automation side effect detected
    // =========================================================================

    @isTest
    static void testSuccess_AutomationFired() {
        AutomationTriggerScenario.injectTriggerFieldValue = 'EXPECTED_AUTOMATION_VALUE';
        try {
            SmokeTestContext ctx = makeContext(new Map<String, Object>{
                'triggerFieldName'          => 'Description',
                'triggerFieldExpectedValue' => 'EXPECTED_AUTOMATION_VALUE'
            });
            Test.startTest();
            ScenarioResult result = new AutomationTriggerScenario().execute(ctx);
            Test.stopTest();

            System.assertEquals(true, result.passed,
                'Scenario must pass when injected field value matches expected; error: ' + result.errorDetail);
            System.assertEquals(AutomationTriggerScenario.SCENARIO_NAME, result.scenarioName);
            System.assertEquals(null, result.errorType);
            System.assertNotEquals(null, result.durationMs);
        } finally {
            AutomationTriggerScenario.injectTriggerFieldValue = null;
        }
    }

    // =========================================================================
    // Automation not fired — real dynamic SOQL path
    // =========================================================================

    @isTest
    static void testAutomationNotFired_RealQuery() {
        // Account.Description is null after a plain SmokeTestDataFactory.createAccount().
        // Since no automation sets Description to 'TRIGGER_SET_VALUE' in the test org,
        // the field check fails → AUTOMATION_NOT_FIRED. This exercises the real SOQL path.
        SmokeTestContext ctx = makeContext(new Map<String, Object>{
            'triggerFieldName'          => 'Description',
            'triggerFieldExpectedValue' => 'TRIGGER_SET_VALUE'
        });
        Test.startTest();
        ScenarioResult result = new AutomationTriggerScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('AUTOMATION_NOT_FIRED', result.errorType);
        System.assert(result.errorDetail.contains('TRIGGER_SET_VALUE'),
            'Error detail must include expected value');
        System.assert(result.errorDetail.contains('Description'),
            'Error detail must include field name');
    }

    @isTest
    static void testAutomationNotFired_InjectedMismatch() {
        AutomationTriggerScenario.injectTriggerFieldValue = 'WRONG_VALUE';
        try {
            SmokeTestContext ctx = makeContext(new Map<String, Object>{
                'triggerFieldName'          => 'Description',
                'triggerFieldExpectedValue' => 'RIGHT_VALUE'
            });
            Test.startTest();
            ScenarioResult result = new AutomationTriggerScenario().execute(ctx);
            Test.stopTest();

            System.assertEquals(false, result.passed);
            System.assertEquals('AUTOMATION_NOT_FIRED', result.errorType);
            System.assert(result.errorDetail.contains('RIGHT_VALUE'),
                'Error detail must show expected value');
            System.assert(result.errorDetail.contains('WRONG_VALUE'),
                'Error detail must show actual value');
        } finally {
            AutomationTriggerScenario.injectTriggerFieldValue = null;
        }
    }

    // =========================================================================
    // Configuration errors
    // =========================================================================

    @isTest
    static void testConfigurationError_MissingFieldName() {
        SmokeTestContext ctx = makeContext(new Map<String, Object>{
            'triggerFieldExpectedValue' => 'SomeValue'
        });
        Test.startTest();
        ScenarioResult result = new AutomationTriggerScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CONFIGURATION_ERROR', result.errorType);
        System.assert(result.errorDetail.contains('triggerFieldName'));
    }

    @isTest
    static void testConfigurationError_MissingExpectedValue() {
        SmokeTestContext ctx = makeContext(new Map<String, Object>{
            'triggerFieldName' => 'Description'
        });
        Test.startTest();
        ScenarioResult result = new AutomationTriggerScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CONFIGURATION_ERROR', result.errorType);
        System.assert(result.errorDetail.contains('triggerFieldExpectedValue'));
    }

    @isTest
    static void testConfigurationError_InvalidFieldName() {
        SmokeTestContext ctx = makeContext(new Map<String, Object>{
            'triggerFieldName'          => 'NotARealField__xyz',
            'triggerFieldExpectedValue' => 'SomeValue'
        });
        Test.startTest();
        ScenarioResult result = new AutomationTriggerScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CONFIGURATION_ERROR', result.errorType);
        System.assert(result.errorDetail.contains('NotARealField__xyz'),
            'Error detail must include the invalid field name');
    }

    @isTest
    static void testConfigurationError_NoParams() {
        SmokeTestContext ctx = makeContext(null);
        Test.startTest();
        ScenarioResult result = new AutomationTriggerScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CONFIGURATION_ERROR', result.errorType);
    }

    // =========================================================================
    // Exception path coverage
    // =========================================================================

    @isTest
    static void testExecuteDmlException() {
        AutomationTriggerScenario.injectException = new DmlException('Simulated automation DML failure');
        try {
            SmokeTestContext ctx = makeContext(new Map<String, Object>{
                'triggerFieldName'          => 'Description',
                'triggerFieldExpectedValue' => 'SomeValue'
            });
            ScenarioResult result = new AutomationTriggerScenario().execute(ctx);
            System.assertEquals(false, result.passed);
            System.assertEquals('DML_EXCEPTION', result.errorType);
            System.assert(result.errorDetail.contains('Simulated automation DML failure'));
        } finally {
            AutomationTriggerScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteUnexpectedError() {
        AutomationTriggerScenario.injectException = new IllegalArgumentException('Unexpected automation error');
        try {
            SmokeTestContext ctx = makeContext(null);
            ScenarioResult result = new AutomationTriggerScenario().execute(ctx);
            System.assertEquals(false, result.passed);
            System.assertEquals('UNEXPECTED_ERROR', result.errorType);
        } finally {
            AutomationTriggerScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteAssertionFailed() {
        AutomationTriggerScenario.triggerAssertFail = true;
        try {
            SmokeTestContext ctx = makeContext(null);
            ScenarioResult result = new AutomationTriggerScenario().execute(ctx);
            System.assertEquals(false, result.passed);
            System.assertEquals('ASSERTION_FAILED', result.errorType);
        } finally {
            AutomationTriggerScenario.triggerAssertFail = false;
        }
    }

    @isTest
    static void testErrorDetailTruncatedAt1000Chars() {
        AutomationTriggerScenario.injectException = new DmlException('A'.repeat(1500));
        try {
            SmokeTestContext ctx = makeContext(null);
            ScenarioResult result = new AutomationTriggerScenario().execute(ctx);
            System.assert(result.errorDetail.length() <= 1000,
                'errorDetail must be capped at 1000 characters');
        } finally {
            AutomationTriggerScenario.injectException = null;
        }
    }

    // =========================================================================
    // Metadata and budget
    // =========================================================================

    @isTest
    static void testGetMetadata() {
        ScenarioMetadata meta = new AutomationTriggerScenario().getMetadata();

        System.assertEquals('Automation_Trigger', meta.scenarioName);
        System.assertEquals(true, meta.isCritical);
        System.assertEquals('Automation', meta.cloudType);
        System.assertEquals(70, meta.executionOrder);
    }

    @isTest
    static void testGetGovernorBudget() {
        GovernorBudgetConfig budget = new AutomationTriggerScenario().getGovernorBudget();

        System.assertEquals(5000, budget.cpuBudgetMs);
        System.assertEquals(50,   budget.soqlBudget);
        System.assertEquals(50,   budget.dmlBudget);
    }

    @isTest
    static void testImplementsISmokeTestScenario() {
        ISmokeTestScenario scenario = new AutomationTriggerScenario();
        System.assertNotEquals(null, scenario.getMetadata());
        System.assertNotEquals(null, scenario.getGovernorBudget());
    }

    // =========================================================================
    // Governor limit budget compliance
    // =========================================================================

    @isTest
    static void testGovernorLimitBudget() {
        // Inject the expected field value so the success path is exercised without
        // requiring org-specific automation to be installed in the test environment
        AutomationTriggerScenario.injectTriggerFieldValue = 'EXPECTED_AUTOMATION_VALUE';
        try {
            SmokeTestContext ctx = makeContext(new Map<String, Object>{
                'triggerFieldName'          => 'Description',
                'triggerFieldExpectedValue' => 'EXPECTED_AUTOMATION_VALUE'
            });
            Test.startTest();
            Integer soqlBefore = Limits.getQueries();
            Integer dmlBefore  = Limits.getDmlStatements();
            Integer cpuBefore  = Limits.getCpuTime();
            new AutomationTriggerScenario().execute(ctx);
            Integer soqlDelta  = Limits.getQueries()        - soqlBefore;
            Integer dmlDelta   = Limits.getDmlStatements()  - dmlBefore;
            Integer cpuDelta   = Limits.getCpuTime()        - cpuBefore;
            Test.stopTest();

            System.assert(soqlDelta <= 50,
                'SOQL budget exceeded: AutomationTriggerScenario used ' + soqlDelta + ' of 50 allowed');
            System.assert(dmlDelta  <= 50,
                'DML budget exceeded: AutomationTriggerScenario used '  + dmlDelta  + ' of 50 allowed');
            System.assert(cpuDelta  <= 5000,
                'CPU budget exceeded: AutomationTriggerScenario used '  + cpuDelta  + 'ms of 5000ms allowed');
        } finally {
            AutomationTriggerScenario.injectTriggerFieldValue = null;
        }
    }
}
