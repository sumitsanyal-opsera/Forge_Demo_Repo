/**
 * Unit tests for CircuitBreakerService.
 * Coverage target: ≥90% on CircuitBreakerService.cls.
 *
 * Test categories:
 *   Initial state        — circuit starts closed
 *   Governor failures    — 1 and 2 don't trip; 3 trips (threshold=3)
 *   Functional failure   — resets the consecutive counter
 *   Success              — resets the consecutive counter
 *   Mixed patterns       — governor+functional+governor+governor = 2 consecutive
 *   Circuit stays open   — success after trip does not close the circuit
 *   reset()              — closes the circuit for next-run use
 *   State persistence    — save/load round-trip across simulated Queueable boundaries
 *   Platform Event       — SmokeTestProgress__e published when circuit trips
 *   Configurable threshold — threshold=1 trips on first governor failure
 *   CMT constructor      — public constructor loads threshold from SmokeTestConfig__mdt
 *   loadState defaults   — fresh execution record returns closed circuit
 */
@isTest
private class CircuitBreakerServiceTest {

    private static Id makeExecId() {
        SmokeTestExecution__c exec = new SmokeTestExecution__c();
        insert exec;
        return exec.Id;
    }

    // Uses @TestVisible constructor to avoid CMT SOQL in most tests
    private static CircuitBreakerService makeService(Id execId) {
        return new CircuitBreakerService(execId, 3);
    }

    // =========================================================================
    // Initial state
    // =========================================================================

    @isTest
    static void testCircuitStartsClosed() {
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        System.assertFalse(svc.isOpen(),   'Circuit must start closed (isOpen=false)');
        System.assertTrue(svc.isClosed(),  'isClosed must return true when circuit is not open');
    }

    // =========================================================================
    // Governor failures — threshold enforcement
    // =========================================================================

    @isTest
    static void testOneGovernorFailureDoesNotTrip() {
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        svc.recordGovernorFailure();

        System.assertFalse(svc.isOpen(),
            '1 governor failure must not trip the circuit (threshold=3)');
    }

    @isTest
    static void testTwoConsecutiveGovernorFailuresDoNotTrip() {
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        svc.recordGovernorFailure();
        svc.recordGovernorFailure();

        System.assertFalse(svc.isOpen(),
            '2 consecutive governor failures must not trip the circuit (threshold=3)');
    }

    @isTest
    static void testThreeConsecutiveGovernorFailuresTrip() {
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        svc.recordGovernorFailure();
        svc.recordGovernorFailure();
        svc.recordGovernorFailure();

        System.assertTrue(svc.isOpen(),
            '3 consecutive governor failures must trip the circuit (threshold=3)');
        System.assertFalse(svc.isClosed(),
            'isClosed must return false when the circuit is open');
    }

    // =========================================================================
    // Functional failure resets counter
    // =========================================================================

    @isTest
    static void testFunctionalFailureResetsConsecutiveCounter() {
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        svc.recordGovernorFailure();
        svc.recordGovernorFailure();
        svc.recordFunctionalFailure(); // resets counter to 0
        svc.recordGovernorFailure();
        svc.recordGovernorFailure();   // only 2 consecutive after reset

        System.assertFalse(svc.isOpen(),
            'Functional failure must reset the consecutive counter — 2 gov+func+2 gov < threshold 3');
    }

    // =========================================================================
    // Success resets counter
    // =========================================================================

    @isTest
    static void testSuccessResetsConsecutiveCounter() {
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        svc.recordGovernorFailure();
        svc.recordGovernorFailure();
        svc.recordSuccess();           // resets counter to 0
        svc.recordGovernorFailure();
        svc.recordGovernorFailure();   // only 2 consecutive after reset

        System.assertFalse(svc.isOpen(),
            'Success must reset the consecutive counter — 2 gov+success+2 gov < threshold 3');
    }

    // =========================================================================
    // Mixed pattern: gov + functional + gov + gov = 2 consecutive, not 3
    // =========================================================================

    @isTest
    static void testGovFuncGovGov_TwoConsecutiveNotThree() {
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        svc.recordGovernorFailure();    // consecutive = 1
        svc.recordFunctionalFailure(); // consecutive = 0  (reset)
        svc.recordGovernorFailure();    // consecutive = 1
        svc.recordGovernorFailure();    // consecutive = 2

        System.assertFalse(svc.isOpen(),
            'Gov+Func+Gov+Gov = 2 consecutive; circuit must not trip with threshold 3');
    }

    // =========================================================================
    // Circuit stays open — success after trip does not auto-close
    // =========================================================================

    @isTest
    static void testCircuitRemainsOpenAfterSuccess() {
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        svc.recordGovernorFailure();
        svc.recordGovernorFailure();
        svc.recordGovernorFailure(); // trips
        svc.recordSuccess();          // resets counter but does NOT close circuit

        System.assertTrue(svc.isOpen(),
            'Circuit must remain open after a success — once open it stays open until reset()');
    }

    @isTest
    static void testCircuitRemainsOpenAfterFunctionalFailure() {
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        svc.recordGovernorFailure();
        svc.recordGovernorFailure();
        svc.recordGovernorFailure();     // trips
        svc.recordFunctionalFailure(); // resets counter but does NOT close circuit

        System.assertTrue(svc.isOpen(),
            'Circuit must remain open after a functional failure — functional failures do not close it');
    }

    // =========================================================================
    // reset() — intended for end-of-run teardown / new-run initialization
    // =========================================================================

    @isTest
    static void testResetClosesCircuit() {
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        svc.recordGovernorFailure();
        svc.recordGovernorFailure();
        svc.recordGovernorFailure(); // trips
        System.assertTrue(svc.isOpen(), 'Precondition: circuit must be open before reset');

        svc.reset();

        System.assertFalse(svc.isOpen(),  'reset() must close the circuit');
        System.assertTrue(svc.isClosed(), 'isClosed() must return true after reset()');
    }

    // =========================================================================
    // State persistence round-trip (simulated Queueable boundary)
    // =========================================================================

    @isTest
    static void testStatePersistenceRoundTrip_TwoFailuresSavedOneMoreTrips() {
        Id execId = makeExecId();
        CircuitBreakerService svc1 = makeService(execId);

        svc1.recordGovernorFailure();
        svc1.recordGovernorFailure();
        System.assertFalse(svc1.isOpen(), 'Precondition: 2 failures should not have tripped the circuit');
        svc1.saveState();

        // Simulate next Queueable link — load from record
        CircuitBreakerService svc2 = CircuitBreakerService.loadState(execId);
        svc2.recordGovernorFailure(); // 3rd consecutive failure

        System.assertTrue(svc2.isOpen(),
            'After loading 2 persisted failures and adding 1 more, circuit must trip');
    }

    @isTest
    static void testSaveAndLoadPreservesCircuitOpenState() {
        Id execId = makeExecId();
        CircuitBreakerService svc1 = makeService(execId);

        svc1.recordGovernorFailure();
        svc1.recordGovernorFailure();
        svc1.recordGovernorFailure(); // trips
        svc1.saveState();

        CircuitBreakerService svc2 = CircuitBreakerService.loadState(execId);

        System.assertTrue(svc2.isOpen(),
            'loadState must restore circuitOpen=true after saving a tripped circuit');
    }

    @isTest
    static void testLoadStateFromFreshExecutionReturnsClosed() {
        Id execId = makeExecId();
        // No saveState() called — CircuitBreakerState__c is null

        CircuitBreakerService svc = CircuitBreakerService.loadState(execId);

        System.assertFalse(svc.isOpen(),
            'loadState on a fresh execution record (no state saved) must return a closed circuit');
    }

    @isTest
    static void testSaveStateUpdatesCircuitBreakerTrippedCheckbox() {
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        svc.recordGovernorFailure();
        svc.recordGovernorFailure();
        svc.recordGovernorFailure(); // trips
        svc.saveState();

        SmokeTestExecution__c exec = [
            SELECT CircuitBreakerTripped__c
            FROM SmokeTestExecution__c
            WHERE Id = :execId
            LIMIT 1
        ];
        System.assertTrue(exec.CircuitBreakerTripped__c,
            'saveState() must set CircuitBreakerTripped__c=true when the circuit is open');
    }

    // =========================================================================
    // Platform Event published when circuit trips
    // =========================================================================

    @isTest
    static void testPlatformEventPublishedOnTrip() {
        CircuitBreakerService.eventPublished = false;
        CircuitBreakerService.lastEventStatus = null;
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        Test.startTest();
        svc.recordGovernorFailure();
        svc.recordGovernorFailure();
        svc.recordGovernorFailure();
        Test.stopTest();

        System.assertTrue(CircuitBreakerService.eventPublished,
            'A SmokeTestProgress__e event must be published when the circuit trips');
        System.assertEquals('CIRCUIT_BREAKER_TRIPPED', CircuitBreakerService.lastEventStatus,
            'Published event must carry CIRCUIT_BREAKER_TRIPPED status');
        // Reset static flag to avoid cross-test pollution
        CircuitBreakerService.eventPublished = false;
        CircuitBreakerService.lastEventStatus = null;
    }

    @isTest
    static void testEventNotPublishedBeforeThreshold() {
        CircuitBreakerService.eventPublished = false;
        Id execId = makeExecId();
        CircuitBreakerService svc = makeService(execId);

        svc.recordGovernorFailure();
        svc.recordGovernorFailure(); // 2 < threshold(3)

        System.assertFalse(CircuitBreakerService.eventPublished,
            'Event must not be published before the threshold is reached');
        CircuitBreakerService.eventPublished = false;
    }

    // =========================================================================
    // Configurable threshold
    // =========================================================================

    @isTest
    static void testThresholdOf1TripsOnFirstGovernorFailure() {
        Id execId = makeExecId();
        CircuitBreakerService svc = new CircuitBreakerService(execId, 1);

        svc.recordGovernorFailure();

        System.assertTrue(svc.isOpen(),
            'With threshold=1, the circuit must trip on the very first governor failure');
    }

    // =========================================================================
    // Public constructor loads threshold from SmokeTestConfig__mdt
    // =========================================================================

    @isTest
    static void testPublicConstructorLoadsThresholdFromCmt() {
        Id execId = makeExecId();

        Test.startTest();
        CircuitBreakerService svc = new CircuitBreakerService(execId);
        Test.stopTest();

        // Default CMT record has CircuitBreakerThreshold__c = 3 — trip 3 times to verify
        svc.recordGovernorFailure();
        svc.recordGovernorFailure();
        svc.recordGovernorFailure();

        System.assertTrue(svc.isOpen(),
            'Public constructor must load threshold=3 from SmokeTestConfig__mdt Default record; '
            + '3 governor failures must trip it');
    }
}
