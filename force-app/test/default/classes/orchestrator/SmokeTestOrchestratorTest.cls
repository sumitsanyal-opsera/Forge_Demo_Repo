@isTest
private class SmokeTestOrchestratorTest {

    // =========================================================================
    // Helpers
    // =========================================================================

    private static SmokeTestExecution__c insertExecution() {
        SmokeTestExecution__c exec = new SmokeTestExecution__c(
            Status__c    = 'In Progress',
            StartTime__c = DateTime.now(),
            TotalScenarios__c = 0
        );
        insert exec;
        return exec;
    }

    private static ScenarioDispatcher.ScenarioConfig makeConfig(String name, Integer order) {
        return new ScenarioDispatcher.ScenarioConfig(
            name, 'ConfigurableMockScenario', order, true, false, null, null, null, null
        );
    }

    private static List<ScenarioDispatcher.ScenarioConfig> threePassConfigs() {
        return new List<ScenarioDispatcher.ScenarioConfig>{
            makeConfig('Scenario_A', 1),
            makeConfig('Scenario_B', 2),
            makeConfig('Scenario_C', 3)
        };
    }

    private static SmokeTestOrchestrator makeOrchestrator(
        Id execId,
        List<ScenarioDispatcher.ScenarioConfig> configs,
        Integer index,
        DateTime startTime,
        Integer timeoutSec
    ) {
        ScenarioDispatcher disp = new ScenarioDispatcher(configs);
        return new SmokeTestOrchestrator(
            execId, configs, index, disp, 'Test', startTime, timeoutSec
        );
    }

    // =========================================================================
    // Test 1 — Full pass suite: 3 scenarios all pass
    // =========================================================================

    @isTest
    static void test_FullPassSuite_ThreeScenarios() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;

        SmokeTestExecution__c exec = insertExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs = threePassConfigs();

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, configs, 0, DateTime.now(), 300));
        Test.stopTest();

        SmokeTestExecution__c updated = [
            SELECT Status__c, OverallResult__c, PassedScenarios__c,
                   FailedScenarios__c, TotalScenarios__c
            FROM SmokeTestExecution__c
            WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed',  updated.Status__c,           'Status should be Completed');
        System.assertEquals('Pass',        updated.OverallResult__c,   'OverallResult should be Pass');
        System.assertEquals(3,             (Integer) updated.PassedScenarios__c, '3 scenarios should pass');
        System.assertEquals(0,             (Integer) updated.FailedScenarios__c, '0 scenarios should fail');

        List<SmokeTestResult__c> results = [
            SELECT Status__c FROM SmokeTestResult__c WHERE Execution__c = :exec.Id
        ];
        System.assertEquals(3, results.size(), 'Should have 3 result records');
        for (SmokeTestResult__c r : results) {
            System.assertEquals('Pass', r.Status__c, 'Each result should be Pass');
        }
    }

    // =========================================================================
    // Test 2 — Partial failure: 2 pass + 1 fail → OverallResult = Partial
    // =========================================================================

    @isTest
    static void test_PartialFailure_OverallResultIsPartial() {
        SmokeTestExecution__c exec = insertExecution();

        // Pre-insert 2 pass results to simulate earlier links completing
        insert new List<SmokeTestResult__c>{
            new SmokeTestResult__c(
                Execution__c = exec.Id, ScenarioName__c = 'Scenario_A',
                Status__c = 'Pass', ExecutionTimeMs__c = 50, ExecutionOrder__c = 0
            ),
            new SmokeTestResult__c(
                Execution__c = exec.Id, ScenarioName__c = 'Scenario_B',
                Status__c = 'Pass', ExecutionTimeMs__c = 50, ExecutionOrder__c = 1
            )
        };

        // Insert 1 fail result
        insert new SmokeTestResult__c(
            Execution__c = exec.Id, ScenarioName__c = 'Scenario_C',
            Status__c = 'Fail', ExecutionTimeMs__c = 50, ExecutionOrder__c = 2
        );

        // Directly call finalize to test aggregate logic
        Test.startTest();
        SmokeTestOrchestrator.doFinalizeForExecution(exec.Id, DateTime.now().addSeconds(-1));
        Test.stopTest();

        SmokeTestExecution__c updated = [
            SELECT Status__c, OverallResult__c, PassedScenarios__c, FailedScenarios__c
            FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c,             'Status should be Completed');
        System.assertEquals('Partial',   updated.OverallResult__c,      'OverallResult should be Partial');
        System.assertEquals(2, (Integer) updated.PassedScenarios__c,    '2 scenarios should pass');
        System.assertEquals(1, (Integer) updated.FailedScenarios__c,    '1 scenario should fail');
    }

    // =========================================================================
    // Test 3 — All fail → OverallResult = Fail
    // =========================================================================

    @isTest
    static void test_AllFail_OverallResultIsFail() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = false;
        ConfigurableMockScenario.injectedErrorType   = 'ASSERTION_FAILURE';
        ConfigurableMockScenario.injectedErrorDetail = 'Mock assertion failure';

        SmokeTestExecution__c exec = insertExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs = new List<ScenarioDispatcher.ScenarioConfig>{
            makeConfig('Fail_A', 1),
            makeConfig('Fail_B', 2)
        };

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, configs, 0, DateTime.now(), 300));
        Test.stopTest();

        SmokeTestExecution__c updated = [
            SELECT Status__c, OverallResult__c, PassedScenarios__c, FailedScenarios__c
            FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c,           'Status should be Completed');
        System.assertEquals('Fail',      updated.OverallResult__c,    'OverallResult should be Fail');
        System.assertEquals(0,           (Integer) updated.PassedScenarios__c, '0 scenarios should pass');
        System.assertEquals(2,           (Integer) updated.FailedScenarios__c, '2 scenarios should fail');
    }

    // =========================================================================
    // Test 4 — Circuit breaker open at start → all scenarios skipped
    // =========================================================================

    @isTest
    static void test_CircuitBreakerOpen_AllScenariosSkipped() {
        SmokeTestExecution__c exec = new SmokeTestExecution__c(
            Status__c              = 'In Progress',
            StartTime__c           = DateTime.now(),
            TotalScenarios__c      = 3,
            CircuitBreakerTripped__c = true,
            CircuitBreakerState__c   = '{"consecutiveGovernorFailures":3,"circuitOpen":true}'
        );
        insert exec;

        List<ScenarioDispatcher.ScenarioConfig> configs = threePassConfigs();

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, configs, 0, DateTime.now(), 300));
        Test.stopTest();

        SmokeTestExecution__c updated = [
            SELECT Status__c, OverallResult__c
            FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c, 'Status should be Completed');

        List<SmokeTestResult__c> results = [
            SELECT Status__c, ErrorMessage__c
            FROM SmokeTestResult__c WHERE Execution__c = :exec.Id
        ];
        System.assertEquals(3, results.size(), 'Should have 3 skipped result records');
        for (SmokeTestResult__c r : results) {
            System.assertEquals('Skipped', r.Status__c, 'Result should be Skipped');
            System.assert(r.ErrorMessage__c.contains('SKIPPED_CIRCUIT_BREAKER'),
                'ErrorMessage should contain SKIPPED_CIRCUIT_BREAKER');
        }
    }

    // =========================================================================
    // Test 5 — Circuit breaker trips during execution (injected CB)
    // =========================================================================

    @isTest
    static void test_CircuitBreakerTrips_RemainingSkipped() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;

        SmokeTestExecution__c exec = insertExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs = threePassConfigs();

        // Inject an already-open CB so the first scenario sees it open
        // (simulates CB tripping between Queueable links)
        CircuitBreakerService openCb = new CircuitBreakerService(exec.Id, 1);
        openCb.recordGovernorFailure(); // trips immediately with threshold=1
        SmokeTestOrchestrator.injectedCb = openCb;

        try {
            Test.startTest();
            System.enqueueJob(makeOrchestrator(exec.Id, configs, 1, DateTime.now(), 300));
            Test.stopTest();

            // The CB was open when link started at index=1, so scenarios 1 and 2 are skipped
            List<SmokeTestResult__c> results = [
                SELECT Status__c, ErrorMessage__c
                FROM SmokeTestResult__c WHERE Execution__c = :exec.Id
            ];
            System.assertEquals(2, results.size(), 'Should have 2 skipped results for scenarios 1 and 2');
            for (SmokeTestResult__c r : results) {
                System.assertEquals('Skipped', r.Status__c, 'Results should be Skipped');
            }
        } finally {
            SmokeTestOrchestrator.injectedCb = null;
        }
    }

    // =========================================================================
    // Test 6 — Suite timeout at start → all scenarios skipped
    // =========================================================================

    @isTest
    static void test_SuiteTimeout_AllScenariosSkipped() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;

        SmokeTestExecution__c exec = insertExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs = threePassConfigs();

        // Pass a startTime in the past (500 seconds ago, timeout=300)
        DateTime pastStart = DateTime.now().addSeconds(-500);

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, configs, 0, pastStart, 300));
        Test.stopTest();

        SmokeTestExecution__c updated = [
            SELECT Status__c FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c, 'Status should be Completed');

        List<SmokeTestResult__c> results = [
            SELECT Status__c, ErrorMessage__c
            FROM SmokeTestResult__c WHERE Execution__c = :exec.Id
        ];
        System.assertEquals(3, results.size(), 'Should have 3 skipped result records');
        for (SmokeTestResult__c r : results) {
            System.assertEquals('Skipped', r.Status__c, 'Result should be Skipped');
            System.assert(r.ErrorMessage__c.contains('SKIPPED_SUITE_TIMEOUT'),
                'ErrorMessage should contain SKIPPED_SUITE_TIMEOUT');
        }
    }

    // =========================================================================
    // Test 7 — Empty scenario list via startExecution
    // =========================================================================

    @isTest
    static void test_EmptyScenarioList_CompletesImmediately() {
        // Inject an empty scenario list via bypassEnqueue + direct factory call
        SmokeTestOrchestrator.bypassEnqueue = true;
        try {
            Test.startTest();
            // Use a dispatcher with empty configs
            ScenarioDispatcher emptyDisp = new ScenarioDispatcher(
                new List<ScenarioDispatcher.ScenarioConfig>()
            );
            SmokeTestExecution__c exec = new SmokeTestExecution__c(
                Status__c = 'In Progress', StartTime__c = DateTime.now(), TotalScenarios__c = 0
            );
            insert exec;
            // Directly finalize empty execution
            SmokeTestOrchestrator.doFinalizeForExecution(exec.Id, DateTime.now());
            Test.stopTest();

            SmokeTestExecution__c updated = [
                SELECT Status__c, OverallResult__c, TotalScenarios__c
                FROM SmokeTestExecution__c WHERE Id = :exec.Id
            ];
            System.assertEquals('Completed', updated.Status__c,         'Status should be Completed');
            System.assertEquals('Pass',       updated.OverallResult__c, 'OverallResult should be Pass');
            System.assertEquals(0, (Integer)  updated.TotalScenarios__c,'TotalScenarios should be 0');

            List<SmokeTestResult__c> results = [
                SELECT Id FROM SmokeTestResult__c WHERE Execution__c = :exec.Id
            ];
            System.assertEquals(0, results.size(), 'No result records should exist');
        } finally {
            SmokeTestOrchestrator.bypassEnqueue = false;
        }
    }

    // =========================================================================
    // Test 8 — Single scenario (no chaining needed)
    // =========================================================================

    @isTest
    static void test_SingleScenario_NoChainingNeeded() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;

        SmokeTestExecution__c exec = insertExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs = new List<ScenarioDispatcher.ScenarioConfig>{
            makeConfig('Only_Scenario', 1)
        };

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, configs, 0, DateTime.now(), 300));
        Test.stopTest();

        SmokeTestExecution__c updated = [
            SELECT Status__c, OverallResult__c, PassedScenarios__c, TotalScenarios__c
            FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c,           'Status should be Completed');
        System.assertEquals('Pass',       updated.OverallResult__c,   'OverallResult should be Pass');
        System.assertEquals(1, (Integer)  updated.PassedScenarios__c, '1 scenario should pass');
        System.assertEquals(1, (Integer)  updated.TotalScenarios__c,  'TotalScenarios should be 1');

        List<SmokeTestResult__c> results = [
            SELECT Status__c FROM SmokeTestResult__c WHERE Execution__c = :exec.Id
        ];
        System.assertEquals(1, results.size(), 'Should have 1 result record');
        System.assertEquals('Pass', results[0].Status__c, 'Result should be Pass');
    }

    // =========================================================================
    // Test 9 — Scenario throws exception → dispatcher catches, result is Fail
    // =========================================================================

    @isTest
    static void test_ScenarioException_ResultIsFail() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldThrowException = true;
        SmokeTestOrchestrator.bypassEnqueue = true;

        try {
            SmokeTestExecution__c exec = insertExecution();
            List<ScenarioDispatcher.ScenarioConfig> configs = new List<ScenarioDispatcher.ScenarioConfig>{
                makeConfig('Error_Scenario', 1)
            };

            Test.startTest();
            System.enqueueJob(makeOrchestrator(exec.Id, configs, 0, DateTime.now(), 300));
            Test.stopTest();

            // shouldThrowException causes dispatcher to catch and return UNEXPECTED_ERROR — result is Fail
            List<SmokeTestResult__c> results = [
                SELECT Status__c FROM SmokeTestResult__c WHERE Execution__c = :exec.Id
            ];
            System.assertEquals(1, results.size(), 'Should have 1 result');
            System.assertEquals('Fail', results[0].Status__c, 'Thrown exception should produce Fail result');
        } finally {
            SmokeTestOrchestrator.bypassEnqueue = false;
        }
    }

    // =========================================================================
    // Test 9b — Top-level error handler: execution marked Failed
    // =========================================================================

    @isTest
    static void test_TopLevelException_ExecutionMarkedFailed() {
        SmokeTestOrchestrator.injectTopLevelError = true;

        try {
            SmokeTestExecution__c exec = insertExecution();
            List<ScenarioDispatcher.ScenarioConfig> configs = new List<ScenarioDispatcher.ScenarioConfig>{
                makeConfig('TopLevel_Error', 1)
            };

            Test.startTest();
            System.enqueueJob(makeOrchestrator(exec.Id, configs, 0, DateTime.now(), 300));
            Test.stopTest();

            SmokeTestExecution__c updated = [
                SELECT Status__c FROM SmokeTestExecution__c WHERE Id = :exec.Id
            ];
            System.assertEquals('Failed', updated.Status__c,
                'Top-level exception should mark execution as Failed');
        } finally {
            SmokeTestOrchestrator.injectTopLevelError = false;
        }
    }

    // =========================================================================
    // Test 10 — bypassEnqueue = true stops after first scenario
    // =========================================================================

    @isTest
    static void test_BypassEnqueue_StopsAfterFirstScenario() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;
        SmokeTestOrchestrator.bypassEnqueue = true;

        try {
            SmokeTestExecution__c exec = insertExecution();
            List<ScenarioDispatcher.ScenarioConfig> configs = threePassConfigs();

            Test.startTest();
            System.enqueueJob(makeOrchestrator(exec.Id, configs, 0, DateTime.now(), 300));
            Test.stopTest();

            // With bypassEnqueue, only 1 result is inserted then finalize is called
            List<SmokeTestResult__c> results = [
                SELECT Status__c FROM SmokeTestResult__c WHERE Execution__c = :exec.Id
            ];
            System.assertEquals(1, results.size(), 'bypassEnqueue should produce 1 result only');

            SmokeTestExecution__c updated = [
                SELECT Status__c FROM SmokeTestExecution__c WHERE Id = :exec.Id
            ];
            System.assertEquals('Completed', updated.Status__c, 'Should still finalize');
        } finally {
            SmokeTestOrchestrator.bypassEnqueue = false;
        }
    }

    // =========================================================================
    // Test 11 — Result fields populated: governor, duration, scenario name
    // =========================================================================

    @isTest
    static void test_ResultRecord_FieldsPopulated() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;
        SmokeTestOrchestrator.bypassEnqueue = true;

        try {
            SmokeTestExecution__c exec = insertExecution();
            List<ScenarioDispatcher.ScenarioConfig> configs = new List<ScenarioDispatcher.ScenarioConfig>{
                makeConfig('Field_Check_Scenario', 1)
            };

            Test.startTest();
            System.enqueueJob(makeOrchestrator(exec.Id, configs, 0, DateTime.now(), 300));
            Test.stopTest();

            SmokeTestResult__c r = [
                SELECT ScenarioName__c, Status__c, ExecutionTimeMs__c, ExecutionOrder__c
                FROM SmokeTestResult__c WHERE Execution__c = :exec.Id LIMIT 1
            ];
            System.assertEquals('Field_Check_Scenario', r.ScenarioName__c, 'ScenarioName should match');
            System.assertEquals('Pass', r.Status__c, 'Status should be Pass');
            System.assertNotEquals(null, r.ExecutionTimeMs__c, 'ExecutionTimeMs should be populated');
            System.assertEquals(0, (Integer) r.ExecutionOrder__c, 'ExecutionOrder should be 0');
        } finally {
            SmokeTestOrchestrator.bypassEnqueue = false;
        }
    }

    // =========================================================================
    // Test 12 — Timeout result status mapping
    // =========================================================================

    @isTest
    static void test_TimedOutScenario_StatusIsTimeout() {
        SmokeTestExecution__c exec = insertExecution();

        // Manually insert a Timeout result and call finalize
        insert new SmokeTestResult__c(
            Execution__c = exec.Id, ScenarioName__c = 'Timeout_Scenario',
            Status__c = 'Timeout', ExecutionTimeMs__c = 30000, ExecutionOrder__c = 0
        );

        Test.startTest();
        SmokeTestOrchestrator.doFinalizeForExecution(exec.Id, DateTime.now().addSeconds(-10));
        Test.stopTest();

        SmokeTestExecution__c updated = [
            SELECT Status__c, OverallResult__c, FailedScenarios__c
            FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c,         'Status should be Completed');
        System.assertEquals('Fail',      updated.OverallResult__c,  'Timeout should produce Fail');
        System.assertEquals(1, (Integer) updated.FailedScenarios__c, 'Timeout counts as failed');
    }

    // =========================================================================
    // Test 13 — Finalize with all-skipped results → OverallResult = Pass
    // =========================================================================

    @isTest
    static void test_AllSkipped_OverallResultIsPass() {
        SmokeTestExecution__c exec = insertExecution();

        // All results are Skipped (e.g., CB tripped before any execute)
        insert new List<SmokeTestResult__c>{
            new SmokeTestResult__c(
                Execution__c = exec.Id, ScenarioName__c = 'Skip_A',
                Status__c = 'Skipped', ExecutionTimeMs__c = 0, ExecutionOrder__c = 0
            ),
            new SmokeTestResult__c(
                Execution__c = exec.Id, ScenarioName__c = 'Skip_B',
                Status__c = 'Skipped', ExecutionTimeMs__c = 0, ExecutionOrder__c = 1
            )
        };

        Test.startTest();
        SmokeTestOrchestrator.doFinalizeForExecution(exec.Id, DateTime.now().addSeconds(-1));
        Test.stopTest();

        SmokeTestExecution__c updated = [
            SELECT Status__c, OverallResult__c
            FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c,         'Status should be Completed');
        System.assertEquals('Pass',      updated.OverallResult__c,  'All-skipped should be Pass');
    }

    // =========================================================================
    // Test 15 — startExecution static factory: creates execution record
    // =========================================================================

    @isTest
    static void test_StartExecution_CreatesExecutionRecord() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        try {
            Test.startTest();
            Id execId = SmokeTestOrchestrator.startExecution('Unit_Test');
            Test.stopTest();

            System.assertNotEquals(null, execId, 'startExecution should return an execution Id');
            SmokeTestExecution__c exec = [
                SELECT Status__c, TriggerSource__c
                FROM SmokeTestExecution__c WHERE Id = :execId
            ];
            System.assertEquals('Unit_Test', exec.TriggerSource__c, 'TriggerSource should be set');
            // Status can be 'In Progress' or 'Completed' depending on CMT scenario availability
            System.assert(
                exec.Status__c == 'In Progress' || exec.Status__c == 'Completed',
                'Execution should be In Progress or Completed'
            );
        } finally {
            SmokeTestOrchestrator.bypassEnqueue = false;
        }
    }

    // =========================================================================
    // Test 14 — Integration: 3 pass scenarios through full chain
    // =========================================================================

    @isTest
    static void test_Integration_ThreeScenariosFullChain() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;

        SmokeTestExecution__c exec = insertExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs = new List<ScenarioDispatcher.ScenarioConfig>{
            makeConfig('Int_A', 10),
            makeConfig('Int_B', 20),
            makeConfig('Int_C', 30)
        };
        ScenarioDispatcher disp = new ScenarioDispatcher(configs);

        Test.startTest();
        System.enqueueJob(new SmokeTestOrchestrator(
            exec.Id, configs, 0, disp, 'Integration_Test', DateTime.now(), 300
        ));
        Test.stopTest();

        SmokeTestExecution__c updated = [
            SELECT Status__c, OverallResult__c, PassedScenarios__c,
                   FailedScenarios__c, TotalScenarios__c, EndTime__c
            FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c,           'Integration: Status=Completed');
        System.assertEquals('Pass',       updated.OverallResult__c,   'Integration: OverallResult=Pass');
        System.assertEquals(3, (Integer)  updated.PassedScenarios__c, 'Integration: 3 passed');
        System.assertEquals(0, (Integer)  updated.FailedScenarios__c, 'Integration: 0 failed');
        System.assertEquals(3, (Integer)  updated.TotalScenarios__c,  'Integration: 3 total');
        System.assertNotEquals(null,       updated.EndTime__c,         'Integration: EndTime populated');

        List<SmokeTestResult__c> results = [
            SELECT ScenarioName__c, Status__c, ExecutionOrder__c
            FROM SmokeTestResult__c WHERE Execution__c = :exec.Id
            ORDER BY ExecutionOrder__c ASC
        ];
        System.assertEquals(3, results.size(), 'Integration: 3 result records');
        System.assertEquals('Int_A', results[0].ScenarioName__c, 'Integration: first scenario name');
        System.assertEquals('Int_B', results[1].ScenarioName__c, 'Integration: second scenario name');
        System.assertEquals('Int_C', results[2].ScenarioName__c, 'Integration: third scenario name');
    }
}
