/**
 * Unit tests for FlowExecutionScenario.
 * Coverage target: ≥90% on FlowExecutionScenario.cls.
 *
 * FlowDefinitionView rows cannot be inserted in @isTest contexts, so the
 * FlowCheckResult injection mechanism (injectFlowCheckResult) is used to
 * mock the Flow metadata query for inactive and success paths.
 * The real SOQL path is exercised via testFlowNotFound_RealQuery.
 */
@isTest
private class FlowExecutionScenarioTest {

    private static SmokeTestContext makeContext(Map<String, Object> params) {
        SmokeTestExecution__c exec = new SmokeTestExecution__c();
        insert exec;
        return new SmokeTestContext(exec.Id, 'test-org', params);
    }

    private static SmokeTestContext makeContextWithFlow(String flowApiName) {
        return makeContext(new Map<String, Object>{ 'flowApiName' => flowApiName });
    }

    private static FlowExecutionScenario.FlowCheckResult makeActiveFlow(String processType) {
        FlowExecutionScenario.FlowCheckResult r = new FlowExecutionScenario.FlowCheckResult();
        r.found       = true;
        r.active      = true;
        r.processType = processType;
        r.label       = 'SMOKE_TEST_MockFlow';
        return r;
    }

    // =========================================================================
    // Success — screen flow (active, no invocation required)
    // =========================================================================

    @isTest
    static void testSuccess_ActiveScreenFlow() {
        FlowExecutionScenario.injectFlowCheckResult = makeActiveFlow('Flow');
        try {
            SmokeTestContext ctx = makeContextWithFlow('SMOKE_TEST_ScreenFlow');
            Test.startTest();
            ScenarioResult result = new FlowExecutionScenario().execute(ctx);
            Test.stopTest();

            System.assertEquals(true, result.passed,
                'Active screen flow verification must pass; error: ' + result.errorDetail);
            System.assertEquals(FlowExecutionScenario.SCENARIO_NAME, result.scenarioName);
            System.assertEquals(null, result.errorType);
            System.assertNotEquals(null, result.durationMs);
        } finally {
            FlowExecutionScenario.injectFlowCheckResult = null;
        }
    }

    // =========================================================================
    // Flow not found — real SOQL path (non-existent API name)
    // =========================================================================

    @isTest
    static void testFlowNotFound_RealQuery() {
        // Exercises the actual FlowDefinitionView SOQL path; a fabricated name
        // is guaranteed not to exist in any org
        SmokeTestContext ctx = makeContextWithFlow('NonExistentFlow_SmokeTest_XYZ_99999');
        Test.startTest();
        ScenarioResult result = new FlowExecutionScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('FLOW_NOT_FOUND', result.errorType);
        System.assert(result.errorDetail.contains('NonExistentFlow_SmokeTest_XYZ_99999'),
            'Error detail must include the queried flow API name');
    }

    // =========================================================================
    // Flow not found — via injection
    // =========================================================================

    @isTest
    static void testFlowNotFound_ViaInjection() {
        FlowExecutionScenario.FlowCheckResult notFound = new FlowExecutionScenario.FlowCheckResult();
        notFound.found = false;
        FlowExecutionScenario.injectFlowCheckResult = notFound;
        try {
            SmokeTestContext ctx = makeContextWithFlow('Some_Flow_Name');
            Test.startTest();
            ScenarioResult result = new FlowExecutionScenario().execute(ctx);
            Test.stopTest();

            System.assertEquals(false, result.passed);
            System.assertEquals('FLOW_NOT_FOUND', result.errorType);
            System.assert(result.errorDetail.contains('Some_Flow_Name'));
        } finally {
            FlowExecutionScenario.injectFlowCheckResult = null;
        }
    }

    // =========================================================================
    // Flow inactive
    // =========================================================================

    @isTest
    static void testFlowInactive() {
        FlowExecutionScenario.FlowCheckResult inactive = new FlowExecutionScenario.FlowCheckResult();
        inactive.found  = true;
        inactive.active = false;
        inactive.label  = 'Deactivated_Flow';
        FlowExecutionScenario.injectFlowCheckResult = inactive;
        try {
            SmokeTestContext ctx = makeContextWithFlow('Deactivated_Flow');
            Test.startTest();
            ScenarioResult result = new FlowExecutionScenario().execute(ctx);
            Test.stopTest();

            System.assertEquals(false, result.passed);
            System.assertEquals('FLOW_INACTIVE', result.errorType);
            System.assert(result.errorDetail.contains('no active version'),
                'Error detail must describe the inactive state');
            System.assert(result.errorDetail.contains('Deactivated_Flow'));
        } finally {
            FlowExecutionScenario.injectFlowCheckResult = null;
        }
    }

    // =========================================================================
    // Flow execution error (autolaunched flow invocation failure)
    // =========================================================================

    @isTest
    static void testFlowExecutionError() {
        FlowExecutionScenario.injectFlowCheckResult = makeActiveFlow('AutoLaunchedFlow');
        FlowExecutionScenario.simulateFlowExecError = true;
        try {
            SmokeTestContext ctx = makeContextWithFlow('SMOKE_TEST_AutoLaunchedFlow');
            Test.startTest();
            ScenarioResult result = new FlowExecutionScenario().execute(ctx);
            Test.stopTest();

            System.assertEquals(false, result.passed);
            System.assertEquals('FLOW_EXECUTION_ERROR', result.errorType);
            System.assert(result.errorDetail.contains('Simulated'));
        } finally {
            FlowExecutionScenario.injectFlowCheckResult = null;
            FlowExecutionScenario.simulateFlowExecError = false;
        }
    }

    // =========================================================================
    // Configuration errors
    // =========================================================================

    @isTest
    static void testConfigurationError_NoFlowApiName() {
        SmokeTestContext ctx = makeContext(null);
        Test.startTest();
        ScenarioResult result = new FlowExecutionScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CONFIGURATION_ERROR', result.errorType);
    }

    @isTest
    static void testConfigurationError_BlankFlowApiName() {
        SmokeTestContext ctx = makeContext(new Map<String, Object>{ 'flowApiName' => '   ' });
        Test.startTest();
        ScenarioResult result = new FlowExecutionScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(false, result.passed);
        System.assertEquals('CONFIGURATION_ERROR', result.errorType);
    }

    // =========================================================================
    // Exception path coverage
    // =========================================================================

    @isTest
    static void testExecuteDmlException() {
        FlowExecutionScenario.injectException = new DmlException('Simulated flow DML failure');
        try {
            ScenarioResult result = new FlowExecutionScenario().execute(makeContextWithFlow('AnyFlow'));
            System.assertEquals(false, result.passed);
            System.assertEquals('DML_EXCEPTION', result.errorType);
        } finally {
            FlowExecutionScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteUnexpectedError() {
        FlowExecutionScenario.injectException = new IllegalArgumentException('Unexpected flow error');
        try {
            ScenarioResult result = new FlowExecutionScenario().execute(makeContextWithFlow('AnyFlow'));
            System.assertEquals(false, result.passed);
            System.assertEquals('UNEXPECTED_ERROR', result.errorType);
        } finally {
            FlowExecutionScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteAssertionFailed() {
        FlowExecutionScenario.triggerAssertFail = true;
        try {
            ScenarioResult result = new FlowExecutionScenario().execute(makeContextWithFlow('AnyFlow'));
            System.assertEquals(false, result.passed);
            System.assertEquals('ASSERTION_FAILED', result.errorType);
        } finally {
            FlowExecutionScenario.triggerAssertFail = false;
        }
    }

    @isTest
    static void testErrorDetailTruncatedAt1000Chars() {
        FlowExecutionScenario.injectException = new DmlException('F'.repeat(1500));
        try {
            ScenarioResult result = new FlowExecutionScenario().execute(makeContextWithFlow('AnyFlow'));
            System.assert(result.errorDetail.length() <= 1000,
                'errorDetail must be capped at 1000 characters');
        } finally {
            FlowExecutionScenario.injectException = null;
        }
    }

    // =========================================================================
    // Metadata and budget
    // =========================================================================

    @isTest
    static void testGetMetadata() {
        ScenarioMetadata meta = new FlowExecutionScenario().getMetadata();

        System.assertEquals('Flow_Execution', meta.scenarioName);
        System.assertEquals(true, meta.isCritical);
        System.assertEquals('Automation', meta.cloudType);
        System.assertEquals(60, meta.executionOrder);
    }

    @isTest
    static void testGetGovernorBudget() {
        GovernorBudgetConfig budget = new FlowExecutionScenario().getGovernorBudget();

        System.assertEquals(5000, budget.cpuBudgetMs);
        System.assertEquals(50,   budget.soqlBudget);
        System.assertEquals(50,   budget.dmlBudget);
    }

    @isTest
    static void testImplementsISmokeTestScenario() {
        ISmokeTestScenario scenario = new FlowExecutionScenario();
        System.assertNotEquals(null, scenario.getMetadata());
        System.assertNotEquals(null, scenario.getGovernorBudget());
    }

    // =========================================================================
    // Governor limit budget compliance
    // =========================================================================

    @isTest
    static void testGovernorLimitBudget() {
        // Inject an active screen flow so no FlowDefinitionView SOQL is needed
        FlowExecutionScenario.injectFlowCheckResult = makeActiveFlow('Flow');
        try {
            SmokeTestContext ctx = makeContextWithFlow('SMOKE_TEST_GovLimitFlow');
            Test.startTest();
            Integer soqlBefore = Limits.getQueries();
            Integer dmlBefore  = Limits.getDmlStatements();
            Integer cpuBefore  = Limits.getCpuTime();
            new FlowExecutionScenario().execute(ctx);
            Integer soqlDelta  = Limits.getQueries()        - soqlBefore;
            Integer dmlDelta   = Limits.getDmlStatements()  - dmlBefore;
            Integer cpuDelta   = Limits.getCpuTime()        - cpuBefore;
            Test.stopTest();

            System.assert(soqlDelta <= 50,
                'SOQL budget exceeded: FlowExecutionScenario used ' + soqlDelta + ' of 50 allowed');
            System.assert(dmlDelta  <= 50,
                'DML budget exceeded: FlowExecutionScenario used '  + dmlDelta  + ' of 50 allowed');
            System.assert(cpuDelta  <= 5000,
                'CPU budget exceeded: FlowExecutionScenario used '  + cpuDelta  + 'ms of 5000ms allowed');
        } finally {
            FlowExecutionScenario.injectFlowCheckResult = null;
        }
    }
}
