@isTest
private class ISmokeTestScenarioTest {

    // =========================================================================
    // Helpers
    // =========================================================================

    private static ScenarioMetadata makeMetadata(String name) {
        return new ScenarioMetadata(name, 'Test scenario', true, 'Sales Cloud', 1);
    }

    private static SmokeTestContext makeContext() {
        return new SmokeTestContext(UserInfo.getUserId(), 'dev-sandbox', null);
    }

    // =========================================================================
    // GovernorBudgetConfig — defaults
    // =========================================================================

    @isTest
    static void testGovernorBudgetConfigDefaultValues() {
        Test.startTest();
        GovernorBudgetConfig cfg = new GovernorBudgetConfig();
        Test.stopTest();

        System.assertEquals(5000, cfg.cpuBudgetMs,    'Default cpuBudgetMs must be 5000');
        System.assertEquals(50,   cfg.soqlBudget,     'Default soqlBudget must be 50');
        System.assertEquals(50,   cfg.dmlBudget,      'Default dmlBudget must be 50');
        System.assertEquals(30,   cfg.timeoutSeconds, 'Default timeoutSeconds must be 30');
    }

    @isTest
    static void testGovernorBudgetConfigCustomValues() {
        Test.startTest();
        GovernorBudgetConfig cfg = new GovernorBudgetConfig(2000, 10, 5, 60);
        Test.stopTest();

        System.assertEquals(2000, cfg.cpuBudgetMs,    'cpuBudgetMs should be 2000');
        System.assertEquals(10,   cfg.soqlBudget,     'soqlBudget should be 10');
        System.assertEquals(5,    cfg.dmlBudget,      'dmlBudget should be 5');
        System.assertEquals(60,   cfg.timeoutSeconds, 'timeoutSeconds should be 60');
    }

    @isTest
    static void testGovernorBudgetConfigRejectsCpuBudgetBelow100() {
        IllegalArgumentException thrown;
        Test.startTest();
        try {
            new GovernorBudgetConfig(99, 50, 50, 30);
        } catch (IllegalArgumentException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null, 'Should throw IllegalArgumentException for cpuBudgetMs < 100');
        System.assert(thrown.getMessage().contains('cpuBudgetMs'),
            'Exception message should mention cpuBudgetMs');
    }

    @isTest
    static void testGovernorBudgetConfigRejectsNullCpuBudget() {
        IllegalArgumentException thrown;
        Test.startTest();
        try {
            new GovernorBudgetConfig(null, 50, 50, 30);
        } catch (IllegalArgumentException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null, 'Should throw IllegalArgumentException for null cpuBudgetMs');
    }

    @isTest
    static void testGovernorBudgetConfigRejectsZeroSoqlBudget() {
        IllegalArgumentException thrown;
        Test.startTest();
        try {
            new GovernorBudgetConfig(5000, 0, 50, 30);
        } catch (IllegalArgumentException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null, 'Should throw IllegalArgumentException for soqlBudget <= 0');
        System.assert(thrown.getMessage().contains('soqlBudget'),
            'Exception message should mention soqlBudget');
    }

    @isTest
    static void testGovernorBudgetConfigRejectsZeroDmlBudget() {
        IllegalArgumentException thrown;
        Test.startTest();
        try {
            new GovernorBudgetConfig(5000, 50, 0, 30);
        } catch (IllegalArgumentException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null, 'Should throw IllegalArgumentException for dmlBudget <= 0');
    }

    @isTest
    static void testGovernorBudgetConfigRejectsZeroTimeoutSeconds() {
        IllegalArgumentException thrown;
        Test.startTest();
        try {
            new GovernorBudgetConfig(5000, 50, 50, 0);
        } catch (IllegalArgumentException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null, 'Should throw IllegalArgumentException for timeoutSeconds <= 0');
    }

    // =========================================================================
    // ScenarioMetadata
    // =========================================================================

    @isTest
    static void testScenarioMetadataStoresAllFields() {
        Test.startTest();
        ScenarioMetadata meta = new ScenarioMetadata(
            'AccountCrud', 'Tests Account CRUD operations', true, 'Sales Cloud', 10);
        Test.stopTest();

        System.assertEquals('AccountCrud',               meta.scenarioName,    'scenarioName should match');
        System.assertEquals('Tests Account CRUD operations', meta.description,  'description should match');
        System.assertEquals(true,                        meta.isCritical,      'isCritical should be true');
        System.assertEquals('Sales Cloud',               meta.cloudType,       'cloudType should match');
        System.assertEquals(10,                          meta.executionOrder,  'executionOrder should be 10');
    }

    @isTest
    static void testScenarioMetadataNullIsCriticalDefaultsFalse() {
        Test.startTest();
        ScenarioMetadata meta = new ScenarioMetadata('Test', null, null, null, null);
        Test.stopTest();

        System.assertEquals(false, meta.isCritical, 'null isCritical should default to false');
    }

    @isTest
    static void testScenarioMetadataRejectsNullName() {
        IllegalArgumentException thrown;
        Test.startTest();
        try {
            new ScenarioMetadata(null, 'desc', false, 'Sales Cloud', 1);
        } catch (IllegalArgumentException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null, 'Should throw IllegalArgumentException for null scenarioName');
        System.assert(thrown.getMessage().contains('scenarioName'),
            'Exception message should mention scenarioName');
    }

    @isTest
    static void testScenarioMetadataRejectsBlankName() {
        IllegalArgumentException thrown;
        Test.startTest();
        try {
            new ScenarioMetadata('   ', 'desc', false, 'Sales Cloud', 1);
        } catch (IllegalArgumentException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null, 'Should throw IllegalArgumentException for blank scenarioName');
    }

    // =========================================================================
    // SmokeTestContext
    // =========================================================================

    @isTest
    static void testSmokeTestContextStoresFields() {
        Id userId = UserInfo.getUserId();
        Map<String, Object> params = new Map<String, Object>{ 'env' => 'dev' };

        Test.startTest();
        SmokeTestContext ctx = new SmokeTestContext(userId, 'dev-sandbox', params);
        Test.stopTest();

        System.assertEquals(userId,        ctx.executionId, 'executionId should match');
        System.assertEquals('dev-sandbox', ctx.targetOrg,   'targetOrg should match');
        System.assertEquals('dev',         ctx.parameters.get('env'), 'parameters should be passed through');
    }

    @isTest
    static void testSmokeTestContextRejectsNullExecutionId() {
        IllegalArgumentException thrown;
        Test.startTest();
        try {
            new SmokeTestContext(null, 'dev-sandbox', null);
        } catch (IllegalArgumentException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null, 'Should throw IllegalArgumentException for null executionId');
        System.assert(thrown.getMessage().contains('executionId'),
            'Exception message should mention executionId');
    }

    @isTest
    static void testSmokeTestContextNullParametersInitializesEmpty() {
        Test.startTest();
        SmokeTestContext ctx = new SmokeTestContext(UserInfo.getUserId(), null, null);
        Test.stopTest();

        System.assert(ctx.parameters != null,   'parameters should not be null when null is passed');
        System.assertEquals(0, ctx.parameters.size(), 'parameters should be an empty map');
    }

    // =========================================================================
    // ScenarioResult
    // =========================================================================

    @isTest
    static void testScenarioResultSuccessFactory() {
        Test.startTest();
        ScenarioResult result = ScenarioResult.success('AccountCrud', 1500L);
        Test.stopTest();

        System.assertEquals(true,          result.passed,       'passed should be true for success');
        System.assertEquals('AccountCrud', result.scenarioName, 'scenarioName should match');
        System.assertEquals(1500L,         result.durationMs,   'durationMs should match');
        System.assertEquals(null,          result.errorType,    'errorType should be null on success');
        System.assertEquals(null,          result.errorDetail,  'errorDetail should be null on success');
    }

    @isTest
    static void testScenarioResultFailureFactory() {
        Test.startTest();
        ScenarioResult result = ScenarioResult.failure(
            'ContactSync', 800L, 'ASSERTION_FAILURE', 'Expected 5 contacts but found 3');
        Test.stopTest();

        System.assertEquals(false,           result.passed,       'passed should be false for failure');
        System.assertEquals('ContactSync',   result.scenarioName, 'scenarioName should match');
        System.assertEquals(800L,            result.durationMs,   'durationMs should match');
        System.assertEquals('ASSERTION_FAILURE', result.errorType, 'errorType should match');
        System.assertEquals('Expected 5 contacts but found 3', result.errorDetail,
            'errorDetail should match');
    }

    // =========================================================================
    // MockSmokeTestScenario — pass path
    // =========================================================================

    @isTest
    static void testMockScenarioPassPath() {
        ScenarioMetadata meta = makeMetadata('LeadConvert');
        SmokeTestContext ctx  = makeContext();

        Test.startTest();
        ISmokeTestScenario scenario = new MockSmokeTestScenario(meta, true);
        ScenarioResult result = scenario.execute(ctx);
        Test.stopTest();

        System.assertEquals(true,          result.passed,       'Pass-configured mock should return passed=true');
        System.assertEquals('LeadConvert', result.scenarioName, 'scenarioName should match metadata');
        System.assertEquals(null,          result.errorType,    'errorType should be null on pass');
    }

    // =========================================================================
    // MockSmokeTestScenario — fail path
    // =========================================================================

    @isTest
    static void testMockScenarioFailPath() {
        ScenarioMetadata meta = makeMetadata('OpportunitySyncCheck');
        SmokeTestContext ctx  = makeContext();

        Test.startTest();
        ISmokeTestScenario scenario = new MockSmokeTestScenario(
            meta, false, 'QUERY_FAILED', 'No Opportunity records returned');
        ScenarioResult result = scenario.execute(ctx);
        Test.stopTest();

        System.assertEquals(false,  result.passed,      'Fail-configured mock should return passed=false');
        System.assertEquals('QUERY_FAILED', result.errorType,  'errorType should match constructor arg');
        System.assertEquals('No Opportunity records returned', result.errorDetail,
            'errorDetail should match constructor arg');
    }

    @isTest
    static void testMockScenarioFailPathWithDefaultErrorType() {
        ScenarioMetadata meta = makeMetadata('CaseCrudCheck');
        SmokeTestContext ctx  = makeContext();

        Test.startTest();
        MockSmokeTestScenario scenario = new MockSmokeTestScenario(meta, false);
        ScenarioResult result = scenario.execute(ctx);
        Test.stopTest();

        System.assertEquals(false,               result.passed,    'Should be failed');
        System.assertEquals('ASSERTION_FAILURE', result.errorType, 'Default errorType should be ASSERTION_FAILURE');
        System.assert(result.errorDetail != null, 'Default errorDetail should not be null');
    }

    // =========================================================================
    // MockSmokeTestScenario — timeout simulation
    // =========================================================================

    @isTest
    static void testMockScenarioTimeoutSimulation() {
        ScenarioMetadata meta = makeMetadata('HeavyQueryScenario');
        SmokeTestContext ctx  = makeContext();

        Test.startTest();
        MockSmokeTestScenario scenario = new MockSmokeTestScenario(
            meta, true, null, null, 35000L, true);
        ScenarioResult result = scenario.execute(ctx);
        Test.stopTest();

        System.assertEquals(false,     result.passed,    'Timeout simulation should return passed=false');
        System.assertEquals('TIMEOUT', result.errorType, 'errorType should be TIMEOUT');
        System.assertEquals(35000L,    result.durationMs,'durationMs should reflect the simulated duration');
    }

    // =========================================================================
    // MockSmokeTestScenario — accessors
    // =========================================================================

    @isTest
    static void testMockScenarioGetMetadata() {
        ScenarioMetadata meta = makeMetadata('AccountCrud');

        Test.startTest();
        MockSmokeTestScenario scenario = new MockSmokeTestScenario(meta, true);
        ScenarioMetadata returned = scenario.getMetadata();
        Test.stopTest();

        System.assertEquals(meta, returned, 'getMetadata() should return the same metadata instance');
    }

    @isTest
    static void testMockScenarioGetGovernorBudget() {
        ScenarioMetadata meta = makeMetadata('AccountCrud');

        Test.startTest();
        MockSmokeTestScenario scenario = new MockSmokeTestScenario(meta, true);
        GovernorBudgetConfig budget = scenario.getGovernorBudget();
        Test.stopTest();

        System.assert(budget != null, 'getGovernorBudget() should return a non-null config');
        System.assertEquals(5000, budget.cpuBudgetMs, 'Default budget should have cpuBudgetMs=5000');
    }
}
