/**
 * Factory helpers for orchestrator security integration tests.
 *
 * Provides pre-configured SecurityHealthCheckResult objects, a controllable
 * ISecurityHealthCheckService mock that queues return values, and SmokeTestExecution__c
 * factory methods for isolation from the broader test suite.
 */
@isTest
public class OrchestratorSecurityTestFixtures {

    // =========================================================================
    // SecurityHealthCheckResult factories
    // =========================================================================

    /** High-scoring pass result (score=90) — clearly above default threshold of 80 */
    public static SecurityHealthCheckResult passResult() {
        return passResult(90);
    }

    public static SecurityHealthCheckResult passResult(Integer score) {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore    = score;
        r.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.PASS;
        r.capturedAt      = DateTime.now();
        return r;
    }

    /** Below-threshold fail result (score=70) */
    public static SecurityHealthCheckResult failResult() {
        return failResult(70);
    }

    public static SecurityHealthCheckResult failResult(Integer score) {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore    = score;
        r.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.FAIL;
        r.capturedAt      = DateTime.now();
        return r;
    }

    /** Error result — simulates Tooling API callout failure */
    public static SecurityHealthCheckResult errorResult() {
        return SecurityHealthCheckResult.error('Tooling API callout failed: HTTP 500');
    }

    /** Skipped result — simulates API budget exhaustion */
    public static SecurityHealthCheckResult skippedResult() {
        return SecurityHealthCheckResult.skipped('API call budget exhausted');
    }

    /** Pass result with one changed risk category for category-diff assertions */
    public static SecurityHealthCheckResult passResultWithCategory(String categoryName, Integer score) {
        SecurityHealthCheckResult r = passResult();
        SecurityHealthCheckResult.SecurityRiskCategory cat =
            new SecurityHealthCheckResult.SecurityRiskCategory();
        cat.categoryName = categoryName;
        cat.score        = score;
        r.riskCategories = new List<SecurityHealthCheckResult.SecurityRiskCategory>{ cat };
        return r;
    }

    // =========================================================================
    // Controllable mock service
    // =========================================================================

    /**
     * Mock that returns results from a FIFO queue.
     * First captureScore() call returns results[0], second returns results[1], etc.
     * If the queue is exhausted, returns errorResult().
     */
    public class QueuedMockSecurityService implements ISecurityHealthCheckService {
        private List<SecurityHealthCheckResult> results;
        public Integer callCount = 0;

        public QueuedMockSecurityService(List<SecurityHealthCheckResult> results) {
            this.results = results != null ? results : new List<SecurityHealthCheckResult>();
        }

        public SecurityHealthCheckResult captureScore() {
            callCount++;
            if (!results.isEmpty()) {
                return results.remove(0);
            }
            return OrchestratorSecurityTestFixtures.errorResult();
        }
    }

    /**
     * Mock that always throws an exception on captureScore() — used to test
     * that pre-capture failures do not block scenario execution.
     */
    public class ThrowingMockSecurityService implements ISecurityHealthCheckService {
        public SecurityHealthCheckResult captureScore() {
            throw new System.CalloutException(
                'Simulated service failure for test coverage'
            );
        }
    }

    // =========================================================================
    // SmokeTestExecution__c factories
    // =========================================================================

    public static SmokeTestExecution__c makeExecution() {
        SmokeTestExecution__c exec = new SmokeTestExecution__c(
            Status__c         = 'In Progress',
            TriggerSource__c  = 'Test',
            StartTime__c      = DateTime.now(),
            TotalScenarios__c = 0
        );
        insert exec;
        return exec;
    }

    // =========================================================================
    // ScenarioConfig factory — single pass scenario for simple integration tests
    // =========================================================================

    public static List<ScenarioDispatcher.ScenarioConfig> onePassConfig() {
        return new List<ScenarioDispatcher.ScenarioConfig>{
            new ScenarioDispatcher.ScenarioConfig(
                'Security_Integration_Scenario', 'ConfigurableMockScenario',
                1, true, false, null, null, null, null
            )
        };
    }
}
