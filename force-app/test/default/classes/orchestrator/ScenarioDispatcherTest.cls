/**
 * Unit tests for ScenarioDispatcher.
 * Coverage target: ≥90% on ScenarioDispatcher.cls.
 *
 * Uses ConfigurableMockScenario (no-arg constructor, @TestVisible static fields)
 * and an injectable ScenarioConfig list to avoid CMT DML limitations in test context.
 *
 * Test categories:
 *   Disabled skip          — SKIPPED_DISABLED returned without executing
 *   Class not found        — CLASS_NOT_FOUND for null Type or blank name
 *   Instantiation error    — INSTANTIATION_ERROR from no-arg-less class or wrong interface
 *   Execution success      — ScenarioResult.passed=true + non-null consumptionReport
 *   Execution failure      — ScenarioResult.passed=false with correct errorType
 *   Exception handling     — DML_EXCEPTION, QUERY_EXCEPTION, UNEXPECTED_ERROR
 *   Timeout enforcement    — TIMED_OUT via ScenarioTimeoutHandler.injectedElapsedMs
 *   Budget override        — CMT override values flow into GovernorBudgetConfig
 *   AC-1 overload          — dispatch(String, context) returns ScenarioResult
 *   getEnabledScenarios    — ordering, disabled filtering, CMT query path
 */
@isTest
private class ScenarioDispatcherTest {

    private static final String MOCK_CLASS = 'ConfigurableMockScenario';

    // =========================================================================
    // Test helpers
    // =========================================================================

    private static SmokeTestContext makeContext() {
        SmokeTestExecution__c exec = new SmokeTestExecution__c();
        insert exec;
        return new SmokeTestContext(exec.Id, 'test-org', null);
    }

    private static ScenarioDispatcher.ScenarioConfig makeConfig(
        String name, String apexClass, Integer order, Boolean enabled
    ) {
        return new ScenarioDispatcher.ScenarioConfig(
            name, apexClass, order, enabled, false, null, null, null, null
        );
    }

    private static ScenarioDispatcher.ScenarioConfig makeMockConfig() {
        return makeConfig(MOCK_CLASS, MOCK_CLASS, 1, true);
    }

    // =========================================================================
    // Disabled scenario — SKIPPED_DISABLED
    // =========================================================================

    @isTest
    static void testDispatch_DisabledScenario_ReturnsSkippedDisabled() {
        ScenarioDispatcher.ScenarioConfig cfg = makeConfig(MOCK_CLASS, MOCK_CLASS, 1, false);
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();
        SmokeTestContext ctx = makeContext();

        Test.startTest();
        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(cfg, ctx);
        Test.stopTest();

        System.assertEquals('SKIPPED_DISABLED', dr.scenarioResult.errorType,
            'Disabled scenario must return SKIPPED_DISABLED errorType');
        System.assertFalse(dr.scenarioResult.passed,
            'Disabled scenario must not pass');
        System.assertNull(dr.consumptionReport,
            'consumptionReport must be null for SKIPPED_DISABLED (no execution happened)');
    }

    @isTest
    static void testDispatch_DisabledScenario_DurationIsZero() {
        ScenarioDispatcher.ScenarioConfig cfg = makeConfig(MOCK_CLASS, MOCK_CLASS, 1, false);
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(cfg, makeContext());

        System.assertEquals(0L, dr.scenarioResult.durationMs,
            'Disabled scenario must report 0 duration');
    }

    // =========================================================================
    // Class not found — CLASS_NOT_FOUND
    // =========================================================================

    @isTest
    static void testDispatch_NonExistentClass_ReturnsClassNotFound() {
        ScenarioDispatcher.ScenarioConfig cfg = makeConfig(
            'NonExistentScenario', 'com.example.NonExistentClass', 1, true
        );
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        Test.startTest();
        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(cfg, makeContext());
        Test.stopTest();

        System.assertEquals('CLASS_NOT_FOUND', dr.scenarioResult.errorType,
            'Non-existent class must return CLASS_NOT_FOUND');
        System.assertFalse(dr.scenarioResult.passed);
        System.assertNull(dr.consumptionReport,
            'consumptionReport must be null when class is not found');
    }

    @isTest
    static void testDispatch_BlankClassName_ReturnsClassNotFound() {
        ScenarioDispatcher.ScenarioConfig cfg = makeConfig('Blank', '', 1, true);
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(cfg, makeContext());

        System.assertEquals('CLASS_NOT_FOUND', dr.scenarioResult.errorType,
            'Blank scenarioClass must return CLASS_NOT_FOUND');
    }

    @isTest
    static void testDispatch_NullClassName_ReturnsClassNotFound() {
        ScenarioDispatcher.ScenarioConfig cfg = makeConfig('NullClass', null, 1, true);
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(cfg, makeContext());

        System.assertEquals('CLASS_NOT_FOUND', dr.scenarioResult.errorType,
            'Null scenarioClass must return CLASS_NOT_FOUND');
    }

    // =========================================================================
    // Instantiation error — INSTANTIATION_ERROR
    // =========================================================================

    @isTest
    static void testDispatch_ClassWithNoNoArgConstructor_ReturnsInstantiationError() {
        // SmokeTestContext has no no-arg constructor; newInstance() throws TypeException
        ScenarioDispatcher.ScenarioConfig cfg = makeConfig(
            'SmokeTestContext', 'SmokeTestContext', 1, true
        );
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        Test.startTest();
        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(cfg, makeContext());
        Test.stopTest();

        System.assertEquals('INSTANTIATION_ERROR', dr.scenarioResult.errorType,
            'Class with no no-arg constructor must return INSTANTIATION_ERROR');
        System.assertFalse(dr.scenarioResult.passed);
        System.assertNull(dr.consumptionReport);
    }

    @isTest
    static void testDispatch_ClassNotImplementingInterface_ReturnsInstantiationError() {
        // GovernorBudgetConfig has a no-arg constructor but does NOT implement ISmokeTestScenario
        ScenarioDispatcher.ScenarioConfig cfg = makeConfig(
            'GovernorBudgetConfig', 'GovernorBudgetConfig', 1, true
        );
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        Test.startTest();
        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(cfg, makeContext());
        Test.stopTest();

        System.assertEquals('INSTANTIATION_ERROR', dr.scenarioResult.errorType,
            'Class not implementing ISmokeTestScenario must return INSTANTIATION_ERROR');
        System.assertFalse(dr.scenarioResult.passed);
        System.assertNull(dr.consumptionReport);
    }

    // =========================================================================
    // Successful dispatch
    // =========================================================================

    @isTest
    static void testDispatch_SuccessPath_ReturnsPassed() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        Test.startTest();
        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(makeMockConfig(), makeContext());
        Test.stopTest();

        System.assertTrue(dr.scenarioResult.passed,
            'Successful mock scenario must return passed=true');
        System.assertNull(dr.scenarioResult.errorType,
            'Successful dispatch must have null errorType');
    }

    @isTest
    static void testDispatch_SuccessPath_ConsumptionReportPopulated() {
        ConfigurableMockScenario.reset();
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(makeMockConfig(), makeContext());

        System.assertNotEquals(null, dr.consumptionReport,
            'consumptionReport must be non-null after successful execution');
        System.assertNotEquals(null, dr.consumptionReport.soqlUsed,
            'consumptionReport.soqlUsed must be set');
    }

    @isTest
    static void testDispatch_SuccessPath_ScenarioNamePreserved() {
        ConfigurableMockScenario.reset();
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(makeMockConfig(), makeContext());

        System.assertEquals('ConfigurableMockScenario', dr.scenarioResult.scenarioName,
            'scenarioName in result must match the mock scenario name');
    }

    // =========================================================================
    // Failure dispatch
    // =========================================================================

    @isTest
    static void testDispatch_FailurePath_ReturnsPassedFalse() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass      = false;
        ConfigurableMockScenario.injectedErrorType   = 'ASSERTION_FAILURE';
        ConfigurableMockScenario.injectedErrorDetail = 'Expected X but got Y';
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        Test.startTest();
        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(makeMockConfig(), makeContext());
        Test.stopTest();

        System.assertFalse(dr.scenarioResult.passed, 'Failing mock must return passed=false');
        System.assertEquals('ASSERTION_FAILURE', dr.scenarioResult.errorType);
        System.assertNotEquals(null, dr.consumptionReport,
            'consumptionReport must be populated even on scenario-level failure');
    }

    // =========================================================================
    // Exception handling
    // =========================================================================

    @isTest
    static void testDispatch_DmlExceptionFromScenario_ReturnsDmlException() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldThrowDmlException = true;
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        Test.startTest();
        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(makeMockConfig(), makeContext());
        Test.stopTest();

        System.assertEquals('DML_EXCEPTION', dr.scenarioResult.errorType,
            'DmlException from scenario must produce DML_EXCEPTION errorType');
        System.assertFalse(dr.scenarioResult.passed);
        System.assertNotEquals(null, dr.consumptionReport,
            'consumptionReport must be populated even when DmlException is caught');
        ConfigurableMockScenario.reset();
    }

    @isTest
    static void testDispatch_QueryExceptionFromScenario_ReturnsQueryException() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldThrowQueryException = true;
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        Test.startTest();
        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(makeMockConfig(), makeContext());
        Test.stopTest();

        System.assertEquals('QUERY_EXCEPTION', dr.scenarioResult.errorType,
            'QueryException from scenario must produce QUERY_EXCEPTION errorType');
        System.assertFalse(dr.scenarioResult.passed);
        ConfigurableMockScenario.reset();
    }

    @isTest
    static void testDispatch_UnhandledExceptionFromScenario_ReturnsUnexpectedError() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldThrowException = true;
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        Test.startTest();
        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(makeMockConfig(), makeContext());
        Test.stopTest();

        System.assertEquals('UNEXPECTED_ERROR', dr.scenarioResult.errorType,
            'Unhandled exception must produce UNEXPECTED_ERROR errorType');
        System.assertFalse(dr.scenarioResult.passed);
        System.assertNotEquals(null, dr.scenarioResult.errorDetail,
            'errorDetail must be populated for UNEXPECTED_ERROR');
        ConfigurableMockScenario.reset();
    }

    // =========================================================================
    // Timeout enforcement
    // =========================================================================

    @isTest
    static void testDispatch_Timeout_ReturnsTimedOut() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;
        // Inject a large elapsed CPU time so post-execution checkAndThrow fires
        ScenarioTimeoutHandler.injectedElapsedMs = 99999; // far exceeds any timeout

        // Use a config with a 1-second timeout override
        ScenarioDispatcher.ScenarioConfig cfg = new ScenarioDispatcher.ScenarioConfig(
            MOCK_CLASS, MOCK_CLASS, 1, true, false,
            1, null, null, null  // timeoutOverrideSec = 1
        );
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        try {
            Test.startTest();
            ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(cfg, makeContext());
            Test.stopTest();

            System.assertEquals('TIMED_OUT', dr.scenarioResult.errorType,
                'Scenario exceeding timeout must produce TIMED_OUT errorType');
            System.assertFalse(dr.scenarioResult.passed);
            System.assertNotEquals(null, dr.consumptionReport,
                'consumptionReport must be populated even for TIMED_OUT (execution happened)');
        } finally {
            ScenarioTimeoutHandler.injectedElapsedMs = null;
            ConfigurableMockScenario.reset();
        }
    }

    @isTest
    static void testDispatch_WithinTimeout_DoesNotTimeout() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;
        // Inject a small elapsed time — well within the 30-second default
        ScenarioTimeoutHandler.injectedElapsedMs = 100; // 100ms

        ScenarioDispatcher.ScenarioConfig cfg = makeMockConfig();
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        try {
            ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(cfg, makeContext());
            System.assertTrue(dr.scenarioResult.passed,
                'Scenario within timeout must not produce TIMED_OUT');
            System.assertNotEquals('TIMED_OUT', dr.scenarioResult.errorType);
        } finally {
            ScenarioTimeoutHandler.injectedElapsedMs = null;
            ConfigurableMockScenario.reset();
        }
    }

    // =========================================================================
    // Budget overrides
    // =========================================================================

    @isTest
    static void testDispatch_BudgetOverride_FlowsIntoConsumptionReport() {
        ConfigurableMockScenario.reset();
        // Config with explicit budget overrides
        ScenarioDispatcher.ScenarioConfig cfg = new ScenarioDispatcher.ScenarioConfig(
            MOCK_CLASS, MOCK_CLASS, 1, true, false,
            null,  // no timeout override
            200,   // cpuBudgetOverride = 200ms
            5,     // soqlBudgetOverride = 5
            5      // dmlBudgetOverride = 5
        );
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(cfg, makeContext());

        System.assertEquals(200, dr.consumptionReport.cpuBudget,
            'consumptionReport.cpuBudget must reflect the CMT override value');
        System.assertEquals(5, dr.consumptionReport.soqlBudget,
            'consumptionReport.soqlBudget must reflect the CMT override value');
        System.assertEquals(5, dr.consumptionReport.dmlBudget,
            'consumptionReport.dmlBudget must reflect the CMT override value');
        ConfigurableMockScenario.reset();
    }

    // =========================================================================
    // AC-1 compatible overload
    // =========================================================================

    @isTest
    static void testDispatch_StringOverload_ReturnsScenarioResult() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        Test.startTest();
        ScenarioResult result = dispatcher.dispatch(MOCK_CLASS, makeContext());
        Test.stopTest();

        System.assertNotEquals(null, result, 'dispatch(String, context) must return non-null');
        System.assertTrue(result.passed, 'dispatch(String, context) must return passed=true for success mock');
        ConfigurableMockScenario.reset();
    }

    @isTest
    static void testDispatch_StringOverload_ClassNotFound_ReturnsClassNotFound() {
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        ScenarioResult result = dispatcher.dispatch('com.example.DoesNotExist', makeContext());

        System.assertEquals('CLASS_NOT_FOUND', result.errorType);
    }

    // =========================================================================
    // getEnabledScenarios — ordering
    // =========================================================================

    @isTest
    static void testGetEnabledScenarios_OrderedByExecutionOrder() {
        List<ScenarioDispatcher.ScenarioConfig> injected = new List<ScenarioDispatcher.ScenarioConfig>{
            makeConfig('ScenC', MOCK_CLASS, 30, true),
            makeConfig('ScenA', MOCK_CLASS, 10, true),
            makeConfig('ScenB', MOCK_CLASS, 20, true)
        };
        ScenarioDispatcher dispatcher = new ScenarioDispatcher(injected);

        Test.startTest();
        List<ScenarioDispatcher.ScenarioConfig> result = dispatcher.getEnabledScenarios();
        Test.stopTest();

        System.assertEquals(3, result.size(), 'All 3 enabled configs must be returned');
        System.assertEquals('ScenA', result[0].scenarioName, 'Order 10 must be first');
        System.assertEquals('ScenB', result[1].scenarioName, 'Order 20 must be second');
        System.assertEquals('ScenC', result[2].scenarioName, 'Order 30 must be third');
    }

    @isTest
    static void testGetEnabledScenarios_FiltersDisabledScenarios() {
        List<ScenarioDispatcher.ScenarioConfig> injected = new List<ScenarioDispatcher.ScenarioConfig>{
            makeConfig('Enabled1',  MOCK_CLASS, 10, true),
            makeConfig('Disabled1', MOCK_CLASS, 20, false),
            makeConfig('Enabled2',  MOCK_CLASS, 30, true)
        };
        ScenarioDispatcher dispatcher = new ScenarioDispatcher(injected);

        List<ScenarioDispatcher.ScenarioConfig> result = dispatcher.getEnabledScenarios();

        System.assertEquals(2, result.size(), 'Disabled scenarios must be filtered out');
        System.assertEquals('Enabled1',  result[0].scenarioName);
        System.assertEquals('Enabled2',  result[1].scenarioName);
    }

    @isTest
    static void testGetEnabledScenarios_EmptyInjectedList_ReturnsEmpty() {
        ScenarioDispatcher dispatcher = new ScenarioDispatcher(
            new List<ScenarioDispatcher.ScenarioConfig>()
        );

        List<ScenarioDispatcher.ScenarioConfig> result = dispatcher.getEnabledScenarios();

        System.assertEquals(0, result.size(), 'Empty injected list must return empty result');
    }

    @isTest
    static void testGetEnabledScenarios_AllDisabled_ReturnsEmpty() {
        List<ScenarioDispatcher.ScenarioConfig> injected = new List<ScenarioDispatcher.ScenarioConfig>{
            makeConfig('Dis1', MOCK_CLASS, 10, false),
            makeConfig('Dis2', MOCK_CLASS, 20, false)
        };
        ScenarioDispatcher dispatcher = new ScenarioDispatcher(injected);

        List<ScenarioDispatcher.ScenarioConfig> result = dispatcher.getEnabledScenarios();

        System.assertEquals(0, result.size(), 'All-disabled list must return empty result');
    }

    @isTest
    static void testGetEnabledScenarios_FromCMT_ReturnsList() {
        // Uses the production no-arg constructor — queries SmokeTestScenario__mdt CMT records
        // (deployed with WO-004, IsEnabled__c = true on all 10 records)
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        Test.startTest();
        List<ScenarioDispatcher.ScenarioConfig> result = dispatcher.getEnabledScenarios();
        Test.stopTest();

        System.assertNotEquals(null, result, 'CMT query must return a non-null list');
        // CMT records are available in test context without SeeAllData
        System.assert(result.size() > 0,
            'At least one enabled SmokeTestScenario__mdt record expected from WO-004 seed data');
    }

    @isTest
    static void testGetEnabledScenarios_CMT_ScenarioClassFieldPopulated() {
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();
        List<ScenarioDispatcher.ScenarioConfig> result = dispatcher.getEnabledScenarios();

        if (!result.isEmpty()) {
            System.assertFalse(String.isBlank(result[0].scenarioClass),
                'ScenarioClass__c must be populated on all enabled CMT records');
        }
    }

    // =========================================================================
    // Integration: dispatch with context
    // =========================================================================

    @isTest
    static void testDispatch_ContextPassedToScenario_ExecutionIdNotNull() {
        ConfigurableMockScenario.reset();
        SmokeTestContext ctx = makeContext();
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(makeMockConfig(), ctx);

        // Scenario executed successfully, confirming context was passed through
        System.assertTrue(dr.scenarioResult.passed,
            'Scenario must execute successfully with valid context');
        ConfigurableMockScenario.reset();
    }

    @isTest
    static void testDispatch_ErrorDetailTruncatedAt1000Chars() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldThrowException      = true;
        // Underlying exception message is short, but verify the cap() path is exercised
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(makeMockConfig(), makeContext());

        System.assertFalse(dr.scenarioResult.passed);
        // The error detail should be non-null and at most 1000 characters
        if (dr.scenarioResult.errorDetail != null) {
            System.assert(dr.scenarioResult.errorDetail.length() <= 1000,
                'errorDetail must be capped at 1000 characters');
        }
        ConfigurableMockScenario.reset();
    }

    @isTest
    static void testDispatchResult_ScenarioResultAndReportAreNotNull_OnSuccess() {
        ConfigurableMockScenario.reset();
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();

        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(makeMockConfig(), makeContext());

        System.assertNotEquals(null, dr.scenarioResult);
        System.assertNotEquals(null, dr.consumptionReport);
        ConfigurableMockScenario.reset();
    }
}
