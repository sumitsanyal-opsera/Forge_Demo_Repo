/**
 * Cooperative circuit breaker that prevents cascading governor limit failures
 * from crashing the entire smoke test suite.
 *
 * Usage pattern (called by ScenarioDispatcher around each scenario):
 *   CircuitBreakerService cb = CircuitBreakerService.loadState(executionId);
 *   if (cb.isOpen()) { markScenarioSkipped(); continue; }
 *   scenario.execute(context);
 *   if (governorLimitExceeded) {
 *       cb.recordGovernorFailure();
 *   } else if (scenarioFailed) {
 *       cb.recordFunctionalFailure();
 *   } else {
 *       cb.recordSuccess();
 *   }
 *   cb.saveState();
 *
 * Design notes:
 *   - The circuit opens after `threshold` (default 3) CONSECUTIVE governor failures.
 *   - Functional failures and successes both reset the consecutive counter.
 *   - Once open, the circuit stays open for the entire execution; reset() is for
 *     end-of-run teardown / new-run initialization only.
 *   - State is persisted to SmokeTestExecution__c (CircuitBreakerState__c JSON +
 *     CircuitBreakerTripped__c checkbox) across Queueable chain links.
 *   - All external operations (DML, EventBus) are wrapped in try-catch so
 *     this service never throws and cannot crash the orchestrator.
 */
global with sharing class CircuitBreakerService {

    private static final Integer DEFAULT_THRESHOLD = 3;

    private Integer consecutiveGovernorFailures = 0;
    private Boolean circuitOpen = false;
    private final Id executionId;
    private final Integer threshold;

    @TestVisible private static Boolean eventPublished = false;
    @TestVisible private static String  lastEventStatus = null;

    // =========================================================================
    // Constructors
    // =========================================================================

    global CircuitBreakerService(Id executionId) {
        this.executionId = executionId;
        this.threshold   = loadThresholdFromCmt();
    }

    @TestVisible
    private CircuitBreakerService(Id executionId, Integer threshold) {
        this.executionId = executionId;
        this.threshold   = (threshold != null && threshold > 0) ? threshold : DEFAULT_THRESHOLD;
    }

    // =========================================================================
    // Public API — state recording
    // =========================================================================

    global void recordSuccess() {
        consecutiveGovernorFailures = 0;
    }

    global void recordFunctionalFailure() {
        consecutiveGovernorFailures = 0;
    }

    global void recordGovernorFailure() {
        consecutiveGovernorFailures++;
        if (consecutiveGovernorFailures >= threshold) {
            circuitOpen = true;
            publishCircuitBreakerEvent();
        }
    }

    global Boolean isOpen() {
        return circuitOpen;
    }

    global Boolean isClosed() {
        return !circuitOpen;
    }

    global void reset() {
        consecutiveGovernorFailures = 0;
        circuitOpen = false;
    }

    // =========================================================================
    // State persistence
    // =========================================================================

    global void saveState() {
        try {
            String stateJson = JSON.serialize(new Map<String, Object>{
                'consecutiveGovernorFailures' => consecutiveGovernorFailures,
                'circuitOpen'                 => circuitOpen
            });
            SmokeTestExecution__c exec = new SmokeTestExecution__c(
                Id                      = executionId,
                CircuitBreakerTripped__c = circuitOpen,
                CircuitBreakerState__c   = stateJson
            );
            update exec;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'CircuitBreakerService.saveState: DML failure — operating with in-memory state only: '
                + e.getMessage());
        }
    }

    global static CircuitBreakerService loadState(Id execId) {
        CircuitBreakerService svc = new CircuitBreakerService(execId);
        try {
            List<SmokeTestExecution__c> rows = [
                SELECT CircuitBreakerTripped__c, CircuitBreakerState__c
                FROM SmokeTestExecution__c
                WHERE Id = :execId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                SmokeTestExecution__c exec = rows[0];
                if (exec.CircuitBreakerState__c != null) {
                    Map<String, Object> state =
                        (Map<String, Object>) JSON.deserializeUntyped(exec.CircuitBreakerState__c);
                    svc.consecutiveGovernorFailures = state.containsKey('consecutiveGovernorFailures')
                        ? Integer.valueOf(state.get('consecutiveGovernorFailures'))
                        : 0;
                    svc.circuitOpen = state.containsKey('circuitOpen')
                        ? (Boolean) state.get('circuitOpen')
                        : (exec.CircuitBreakerTripped__c == true);
                } else {
                    svc.circuitOpen = (exec.CircuitBreakerTripped__c == true);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'CircuitBreakerService.loadState: failed to restore state — using defaults: '
                + e.getMessage());
        }
        return svc;
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private Integer loadThresholdFromCmt() {
        try {
            List<SmokeTestConfig__mdt> configs = [
                SELECT CircuitBreakerThreshold__c
                FROM SmokeTestConfig__mdt
                WHERE DeveloperName = 'Default'
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!configs.isEmpty() && configs[0].CircuitBreakerThreshold__c != null) {
                Integer t = Integer.valueOf(configs[0].CircuitBreakerThreshold__c);
                return t > 0 ? t : DEFAULT_THRESHOLD;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'CircuitBreakerService: could not load CircuitBreakerThreshold__c — using default 3: '
                + e.getMessage());
        }
        return DEFAULT_THRESHOLD;
    }

    private void publishCircuitBreakerEvent() {
        try {
            SmokeTestProgress__e evt = new SmokeTestProgress__e(
                ExecutionId__c    = String.valueOf(executionId),
                ScenarioStatus__c = 'CIRCUIT_BREAKER_TRIPPED',
                CurrentPhase__c   = 'Circuit breaker tripped after '
                    + consecutiveGovernorFailures
                    + ' consecutive governor limit failures'
            );
            EventBus.publish(evt);
            eventPublished = true;
            lastEventStatus = 'CIRCUIT_BREAKER_TRIPPED';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'CircuitBreakerService: failed to publish SmokeTestProgress__e: ' + e.getMessage());
        }
    }
}
