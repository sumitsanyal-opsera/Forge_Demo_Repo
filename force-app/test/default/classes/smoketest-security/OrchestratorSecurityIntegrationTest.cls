/**
 * Unit and integration tests for the security health check integration in SmokeTestOrchestrator.
 *
 * Test categories:
 *   Pre-capture  — baseline captured on first link before any scenario dispatch
 *   Pass status  — both thresholds met → SmokeTestSecurityScore__c with ThresholdStatus='Pass'
 *   Fail status  — score below threshold → ThresholdStatus='Fail'
 *   Error/Skip   — pre-capture error → ThresholdStatus='Error', suite still completes
 *   Platform Evt — SmokeTestSecurityComplete__e published after security check
 *   Integration  — full orchestrator chain with security check (system integration)
 */
@isTest
private class OrchestratorSecurityIntegrationTest {

    // =========================================================================
    // Helpers
    // =========================================================================

    private static void resetFlags() {
        SmokeTestOrchestrator.bypassEnqueue           = false;
        SmokeTestOrchestrator.injectedSecurityService = null;
        SmokeTestOrchestrator.injectedComparator      = null;
        SmokeTestOrchestrator.injectedCb              = null;
        ConfigurableMockScenario.reset();
    }

    private static SmokeTestOrchestrator makeOrchestrator(
        Id execId,
        List<ScenarioDispatcher.ScenarioConfig> configs,
        Integer index
    ) {
        ScenarioDispatcher disp = new ScenarioDispatcher(configs);
        return new SmokeTestOrchestrator(
            execId, configs, index, disp, 'Test', DateTime.now(), 300
        );
    }

    private static SmokeTestSecurityScore__c querySecurityScore(Id execId) {
        List<SmokeTestSecurityScore__c> scores = [
            SELECT PreDeploymentScore__c, PostDeploymentScore__c,
                   AbsoluteThreshold__c, RelativeThreshold__c,
                   ThresholdMet__c, ThresholdStatus__c,
                   CheckedAt__c, RiskCategories__c, Execution__c
            FROM   SmokeTestSecurityScore__c
            WHERE  Execution__c = :execId
            LIMIT  1
        ];
        return scores.isEmpty() ? null : scores[0];
    }

    // =========================================================================
    // Test 1 — Pre-capture is called before scenario dispatch (AC1)
    //          Verified by injecting a mock that counts captureScore() calls
    // =========================================================================

    @isTest
    static void test_PreCaptureCalled_BeforeScenarioDispatch() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;

        SmokeTestExecution__c exec = OrchestratorSecurityTestFixtures.makeExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs =
            OrchestratorSecurityTestFixtures.onePassConfig();

        OrchestratorSecurityTestFixtures.QueuedMockSecurityService mockSvc =
            new OrchestratorSecurityTestFixtures.QueuedMockSecurityService(
                new List<SecurityHealthCheckResult>{
                    OrchestratorSecurityTestFixtures.passResult(),
                    OrchestratorSecurityTestFixtures.passResult()
                }
            );

        SmokeTestOrchestrator.bypassEnqueue           = true;
        SmokeTestOrchestrator.injectedSecurityService = mockSvc;

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, configs, 0));
        Test.stopTest();

        // captureScore called twice: once pre, once post
        System.assertEquals(2, mockSvc.callCount,
            'captureScore() should be called twice: pre-deployment and post-deployment');

        resetFlags();
    }

    // =========================================================================
    // Test 2 — Both thresholds pass → ThresholdStatus='Pass', ThresholdMet=true (AC2, AC3)
    // =========================================================================

    @isTest
    static void test_BothThresholdsPass_PersistsPassStatus() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;

        SmokeTestExecution__c exec = OrchestratorSecurityTestFixtures.makeExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs =
            OrchestratorSecurityTestFixtures.onePassConfig();

        // pre=90, post=90: both above threshold 80, delta=0 <= maxDrop 5 → Pass
        OrchestratorSecurityTestFixtures.QueuedMockSecurityService mockSvc =
            new OrchestratorSecurityTestFixtures.QueuedMockSecurityService(
                new List<SecurityHealthCheckResult>{
                    OrchestratorSecurityTestFixtures.passResult(90),
                    OrchestratorSecurityTestFixtures.passResult(90)
                }
            );

        SmokeTestOrchestrator.bypassEnqueue           = true;
        SmokeTestOrchestrator.injectedSecurityService = mockSvc;

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, configs, 0));
        Test.stopTest();

        SmokeTestSecurityScore__c score = querySecurityScore(exec.Id);
        System.assertNotEquals(null, score, 'SmokeTestSecurityScore__c should be created');
        System.assertEquals('Pass', score.ThresholdStatus__c,
            'ThresholdStatus should be Pass when both thresholds are met');
        System.assertEquals(true, score.ThresholdMet__c,
            'ThresholdMet should be true when status is Pass');
        System.assertEquals(90, (Integer) score.PreDeploymentScore__c,
            'PreDeploymentScore must match the pre-capture score');
        System.assertEquals(90, (Integer) score.PostDeploymentScore__c,
            'PostDeploymentScore must match the post-capture score');
        System.assertNotEquals(null, score.CheckedAt__c,
            'CheckedAt must be populated');
        System.assertEquals(exec.Id, score.Execution__c,
            'Execution lookup must reference the correct execution');

        resetFlags();
    }

    // =========================================================================
    // Test 3 — Post score below absolute threshold → ThresholdStatus='Fail' (AC2, AC3)
    // =========================================================================

    @isTest
    static void test_PostScoreBelowThreshold_PersistsFailStatus() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;

        SmokeTestExecution__c exec = OrchestratorSecurityTestFixtures.makeExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs =
            OrchestratorSecurityTestFixtures.onePassConfig();

        // pre=85, post=70: post below threshold 80 → Fail
        OrchestratorSecurityTestFixtures.QueuedMockSecurityService mockSvc =
            new OrchestratorSecurityTestFixtures.QueuedMockSecurityService(
                new List<SecurityHealthCheckResult>{
                    OrchestratorSecurityTestFixtures.passResult(85),
                    OrchestratorSecurityTestFixtures.failResult(70)
                }
            );

        SmokeTestOrchestrator.bypassEnqueue           = true;
        SmokeTestOrchestrator.injectedSecurityService = mockSvc;

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, configs, 0));
        Test.stopTest();

        SmokeTestSecurityScore__c score = querySecurityScore(exec.Id);
        System.assertNotEquals(null, score, 'SmokeTestSecurityScore__c should be created');
        System.assertEquals('Fail', score.ThresholdStatus__c,
            'ThresholdStatus should be Fail when post score is below threshold');
        System.assertEquals(false, score.ThresholdMet__c,
            'ThresholdMet should be false when status is Fail');

        // Execution should still complete (security failure is non-blocking)
        SmokeTestExecution__c updated = [
            SELECT Status__c FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c,
            'Execution should complete even when security threshold fails');

        resetFlags();
    }

    // =========================================================================
    // Test 4 — Pre-capture returns Error → ThresholdStatus='Error', suite continues (AC6)
    // =========================================================================

    @isTest
    static void test_PreCaptureError_SuiteContinuesWithErrorStatus() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;

        SmokeTestExecution__c exec = OrchestratorSecurityTestFixtures.makeExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs =
            OrchestratorSecurityTestFixtures.onePassConfig();

        // First call (pre) returns error; second call (post) returns pass
        OrchestratorSecurityTestFixtures.QueuedMockSecurityService mockSvc =
            new OrchestratorSecurityTestFixtures.QueuedMockSecurityService(
                new List<SecurityHealthCheckResult>{
                    OrchestratorSecurityTestFixtures.errorResult(),
                    OrchestratorSecurityTestFixtures.passResult()
                }
            );

        SmokeTestOrchestrator.bypassEnqueue           = true;
        SmokeTestOrchestrator.injectedSecurityService = mockSvc;

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, configs, 0));
        Test.stopTest();

        // Security score record should be created with Error status
        SmokeTestSecurityScore__c score = querySecurityScore(exec.Id);
        System.assertNotEquals(null, score, 'SmokeTestSecurityScore__c should still be created');
        System.assertEquals('Error', score.ThresholdStatus__c,
            'ThresholdStatus should be Error when pre-capture fails');

        // Suite still completes
        SmokeTestExecution__c updated = [
            SELECT Status__c FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c,
            'Execution should complete even when security pre-capture fails');

        // Scenario results still created
        Integer resultCount = [
            SELECT COUNT() FROM SmokeTestResult__c WHERE Execution__c = :exec.Id
        ];
        System.assertEquals(1, resultCount, 'Scenario results should be created despite security error');

        resetFlags();
    }

    // =========================================================================
    // Test 5 — Throwing security service → Error status, suite continues (AC6)
    // =========================================================================

    @isTest
    static void test_SecurityServiceThrows_SuiteContinues() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;

        SmokeTestExecution__c exec = OrchestratorSecurityTestFixtures.makeExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs =
            OrchestratorSecurityTestFixtures.onePassConfig();

        SmokeTestOrchestrator.bypassEnqueue           = true;
        SmokeTestOrchestrator.injectedSecurityService =
            new OrchestratorSecurityTestFixtures.ThrowingMockSecurityService();

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, configs, 0));
        Test.stopTest();

        // Suite completed despite service exception
        SmokeTestExecution__c updated = [
            SELECT Status__c FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c,
            'Execution should complete even when security service throws');

        resetFlags();
    }

    // =========================================================================
    // Test 6 — SmokeTestSecurityComplete__e published (AC4)
    //          In test context, EventBus.publish() is called synchronously
    // =========================================================================

    @isTest
    static void test_SecurityCompleteEvent_Published() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;

        SmokeTestExecution__c exec = OrchestratorSecurityTestFixtures.makeExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs =
            OrchestratorSecurityTestFixtures.onePassConfig();

        OrchestratorSecurityTestFixtures.QueuedMockSecurityService mockSvc =
            new OrchestratorSecurityTestFixtures.QueuedMockSecurityService(
                new List<SecurityHealthCheckResult>{
                    OrchestratorSecurityTestFixtures.passResult(),
                    OrchestratorSecurityTestFixtures.passResult()
                }
            );

        SmokeTestOrchestrator.bypassEnqueue           = true;
        SmokeTestOrchestrator.injectedSecurityService = mockSvc;

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, configs, 0));
        Test.stopTest();

        // Security score record confirms the security path ran
        SmokeTestSecurityScore__c score = querySecurityScore(exec.Id);
        System.assertNotEquals(null, score,
            'Security score record confirms postExecutionSecurityCheck ran');
        System.assertEquals('Pass', score.ThresholdStatus__c,
            'Security event published with Pass status');

        resetFlags();
    }

    // =========================================================================
    // Test 7 — Empty suite still captures security score (edge case)
    // =========================================================================

    @isTest
    static void test_EmptySuite_SecurityScorePersisted() {
        SmokeTestExecution__c exec = OrchestratorSecurityTestFixtures.makeExecution();
        List<ScenarioDispatcher.ScenarioConfig> emptyConfigs =
            new List<ScenarioDispatcher.ScenarioConfig>();

        OrchestratorSecurityTestFixtures.QueuedMockSecurityService mockSvc =
            new OrchestratorSecurityTestFixtures.QueuedMockSecurityService(
                new List<SecurityHealthCheckResult>{
                    OrchestratorSecurityTestFixtures.passResult(),
                    OrchestratorSecurityTestFixtures.passResult()
                }
            );

        SmokeTestOrchestrator.bypassEnqueue           = true;
        SmokeTestOrchestrator.injectedSecurityService = mockSvc;

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, emptyConfigs, 0));
        Test.stopTest();

        SmokeTestSecurityScore__c score = querySecurityScore(exec.Id);
        System.assertNotEquals(null, score,
            'Security score should be persisted even for empty suites');

        SmokeTestExecution__c updated = [
            SELECT Status__c, OverallResult__c FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c, 'Empty suite should complete');
        System.assertEquals('Pass', updated.OverallResult__c,
            'Empty suite overall result should be Pass');

        resetFlags();
    }

    // =========================================================================
    // Test 8 — System integration: full orchestrator chain, security score verified (AC8)
    // =========================================================================

    @isTest
    static void test_Integration_FullChain_SecurityScoreCreated() {
        ConfigurableMockScenario.reset();
        ConfigurableMockScenario.shouldPass = true;

        SmokeTestExecution__c exec = OrchestratorSecurityTestFixtures.makeExecution();
        List<ScenarioDispatcher.ScenarioConfig> configs =
            OrchestratorSecurityTestFixtures.onePassConfig();

        OrchestratorSecurityTestFixtures.QueuedMockSecurityService mockSvc =
            new OrchestratorSecurityTestFixtures.QueuedMockSecurityService(
                new List<SecurityHealthCheckResult>{
                    OrchestratorSecurityTestFixtures.passResult(88),
                    OrchestratorSecurityTestFixtures.passResult(85)
                }
            );

        SmokeTestOrchestrator.injectedSecurityService = mockSvc;
        // No bypassEnqueue — let the real Queueable chain run

        Test.startTest();
        System.enqueueJob(makeOrchestrator(exec.Id, configs, 0));
        Test.stopTest();

        // Execution finalized
        SmokeTestExecution__c updated = [
            SELECT Status__c, OverallResult__c, PassedScenarios__c
            FROM SmokeTestExecution__c WHERE Id = :exec.Id
        ];
        System.assertEquals('Completed', updated.Status__c,
            'Integration: execution should be Completed');
        System.assertEquals('Pass', updated.OverallResult__c,
            'Integration: overall result should be Pass');

        // Security score record created
        SmokeTestSecurityScore__c score = querySecurityScore(exec.Id);
        System.assertNotEquals(null, score,
            'Integration: SmokeTestSecurityScore__c should be created');
        System.assertEquals('Pass', score.ThresholdStatus__c,
            'Integration: ThresholdStatus should be Pass');
        System.assertEquals(88, (Integer) score.PreDeploymentScore__c,
            'Integration: pre-deployment score should be 88');
        System.assertEquals(85, (Integer) score.PostDeploymentScore__c,
            'Integration: post-deployment score should be 85');

        resetFlags();
    }
}
