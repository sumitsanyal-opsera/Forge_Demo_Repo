/**
 * Tests for DeploymentCompleteTriggerHandler.
 *
 * Tests use direct handler invocation (handleEvents) for deterministic unit
 * tests plus one EventBus.publish() integration test to verify the trigger
 * fires correctly in the Platform Event context.
 *
 * bypassEnqueue is set to true so startExecution() inserts the execution
 * record synchronously without spawning a Queueable that would fail in tests.
 */
@isTest
private class DeploymentCompleteTriggerHandlerTest {

    private static final String DEPLOYMENT_ID = 'deploy-abc-001';

    // =========================================================================
    // Setup helpers
    // =========================================================================

    private static DeploymentComplete__e makeEvent(String deploymentId) {
        DeploymentComplete__e evt = new DeploymentComplete__e();
        evt.DeploymentId__c = deploymentId;
        return evt;
    }

    // Reset injectable flags after each test
    @TestSetup
    static void setup() {
        // No data setup needed — each test manages its own state
    }

    private static void resetFlags() {
        SmokeTestOrchestrator.bypassEnqueue        = false;
        DeploymentCompleteTriggerHandler.shadowModeOverride = null;
        DeploymentCompleteTriggerHandler.dmlOverride        = null;
    }

    // =========================================================================
    // Test 1 — valid event creates SmokeTestExecution__c
    // =========================================================================

    @isTest
    static void validEvent_createsExecution() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        DeploymentCompleteTriggerHandler.shadowModeOverride = false;

        Test.startTest();
        DeploymentCompleteTriggerHandler.handleEvents(
            new List<DeploymentComplete__e>{ makeEvent(DEPLOYMENT_ID) }
        );
        Test.stopTest();

        List<SmokeTestExecution__c> execs = [
            SELECT TriggerSource__c, DeploymentId__c
            FROM   SmokeTestExecution__c
            WHERE  DeploymentId__c = :DEPLOYMENT_ID
        ];
        System.assertEquals(1, execs.size(), 'Exactly one execution should be created');
        System.assertEquals('Platform Event', execs[0].TriggerSource__c,
            'TriggerSource should be Platform Event');
        System.assertEquals(DEPLOYMENT_ID, execs[0].DeploymentId__c,
            'DeploymentId should be set on the execution');

        resetFlags();
    }

    // =========================================================================
    // Test 2 — shadow mode skips execution
    // =========================================================================

    @isTest
    static void shadowMode_skipsExecution() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        DeploymentCompleteTriggerHandler.shadowModeOverride = true;

        Test.startTest();
        DeploymentCompleteTriggerHandler.handleEvents(
            new List<DeploymentComplete__e>{ makeEvent(DEPLOYMENT_ID) }
        );
        Test.stopTest();

        Integer execCount = [
            SELECT COUNT()
            FROM   SmokeTestExecution__c
            WHERE  DeploymentId__c = :DEPLOYMENT_ID
        ];
        System.assertEquals(0, execCount,
            'Shadow mode must not create a SmokeTestExecution__c record');

        resetFlags();
    }

    // =========================================================================
    // Test 3 — shadow mode creates audit record
    // =========================================================================

    @isTest
    static void shadowMode_createsAuditRecord() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        DeploymentCompleteTriggerHandler.shadowModeOverride = true;

        Test.startTest();
        DeploymentCompleteTriggerHandler.handleEvents(
            new List<DeploymentComplete__e>{ makeEvent(DEPLOYMENT_ID) }
        );
        Test.stopTest();

        Integer auditCount = [
            SELECT COUNT()
            FROM   SmokeTestAuditLog__c
            WHERE  ResourceId__c = :DEPLOYMENT_ID
            AND    Outcome__c     = 'SHADOW_MODE_SKIPPED'
        ];
        System.assertEquals(1, auditCount,
            'Shadow mode should write one audit record with SHADOW_MODE_SKIPPED outcome');

        resetFlags();
    }

    // =========================================================================
    // Test 4 — duplicate event (same DeploymentId within 5 minutes)
    // =========================================================================

    @isTest
    static void duplicateEvent_skipsExecution() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        DeploymentCompleteTriggerHandler.shadowModeOverride = false;

        // Pre-create an execution for the same deploymentId
        SmokeTestExecution__c existing = new SmokeTestExecution__c(
            Status__c        = 'In Progress',
            TriggerSource__c = 'Platform Event',
            StartTime__c     = DateTime.now().addMinutes(-2),
            DeploymentId__c  = DEPLOYMENT_ID
        );
        insert existing;

        Test.startTest();
        DeploymentCompleteTriggerHandler.handleEvents(
            new List<DeploymentComplete__e>{ makeEvent(DEPLOYMENT_ID) }
        );
        Test.stopTest();

        Integer execCount = [
            SELECT COUNT()
            FROM   SmokeTestExecution__c
            WHERE  DeploymentId__c = :DEPLOYMENT_ID
        ];
        System.assertEquals(1, execCount,
            'Duplicate event must not create a second execution — only the pre-existing one should exist');

        resetFlags();
    }

    // =========================================================================
    // Test 5 — null/blank DeploymentId skips event
    // =========================================================================

    @isTest
    static void nullDeploymentId_skipsEvent() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        DeploymentCompleteTriggerHandler.shadowModeOverride = false;

        DeploymentComplete__e evt = new DeploymentComplete__e();
        // DeploymentId__c intentionally not set (null)

        Test.startTest();
        DeploymentCompleteTriggerHandler.handleEvents(
            new List<DeploymentComplete__e>{ evt }
        );
        Test.stopTest();

        Integer execCount = [SELECT COUNT() FROM SmokeTestExecution__c];
        System.assertEquals(0, execCount,
            'Event with null DeploymentId should be skipped — no execution created');

        resetFlags();
    }

    // =========================================================================
    // Test 6 — blank DeploymentId skips event
    // =========================================================================

    @isTest
    static void blankDeploymentId_skipsEvent() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        DeploymentCompleteTriggerHandler.shadowModeOverride = false;

        Test.startTest();
        DeploymentCompleteTriggerHandler.handleEvents(
            new List<DeploymentComplete__e>{ makeEvent('') }
        );
        Test.stopTest();

        Integer execCount = [SELECT COUNT() FROM SmokeTestExecution__c];
        System.assertEquals(0, execCount,
            'Event with blank DeploymentId should be skipped — no execution created');

        resetFlags();
    }

    // =========================================================================
    // Test 7 — bulk events: three different deployment IDs → three executions
    // =========================================================================

    @isTest
    static void bulkEvents_allValidIds_createsThreeExecutions() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        DeploymentCompleteTriggerHandler.shadowModeOverride = false;

        List<DeploymentComplete__e> events = new List<DeploymentComplete__e>{
            makeEvent('bulk-deploy-001'),
            makeEvent('bulk-deploy-002'),
            makeEvent('bulk-deploy-003')
        };

        Test.startTest();
        DeploymentCompleteTriggerHandler.handleEvents(events);
        Test.stopTest();

        Integer execCount = [
            SELECT COUNT()
            FROM   SmokeTestExecution__c
            WHERE  DeploymentId__c IN ('bulk-deploy-001', 'bulk-deploy-002', 'bulk-deploy-003')
        ];
        System.assertEquals(3, execCount,
            'Three valid events with distinct deployment IDs should produce 3 executions');

        resetFlags();
    }

    // =========================================================================
    // Test 8 — bulk events with mixed valid/invalid/duplicate payloads
    // =========================================================================

    @isTest
    static void bulkEvents_mixedPayloads_createsOnlyValidNonDuplicateExecutions() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        DeploymentCompleteTriggerHandler.shadowModeOverride = false;

        // Pre-create duplicate
        insert new SmokeTestExecution__c(
            Status__c        = 'In Progress',
            TriggerSource__c = 'Platform Event',
            StartTime__c     = DateTime.now().addMinutes(-1),
            DeploymentId__c  = 'mixed-dupe'
        );

        List<DeploymentComplete__e> events = new List<DeploymentComplete__e>{
            makeEvent('mixed-valid-1'),   // valid
            makeEvent('mixed-valid-1'),   // same-batch duplicate → skipped
            makeEvent('mixed-dupe'),      // DB duplicate → skipped
            makeEvent(null),              // null → skipped
            makeEvent('mixed-valid-2')    // valid
        };

        Test.startTest();
        DeploymentCompleteTriggerHandler.handleEvents(events);
        Test.stopTest();

        Integer newExecCount = [
            SELECT COUNT()
            FROM   SmokeTestExecution__c
            WHERE  DeploymentId__c IN ('mixed-valid-1', 'mixed-valid-2')
        ];
        System.assertEquals(2, newExecCount,
            'Only 2 new executions should be created (valid non-duplicate IDs)');

        resetFlags();
    }

    // =========================================================================
    // Test 9 — same-batch duplicate (same ID appears twice in one invocation)
    // =========================================================================

    @isTest
    static void sameBatchDuplicate_createsOnlyOneExecution() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        DeploymentCompleteTriggerHandler.shadowModeOverride = false;

        List<DeploymentComplete__e> events = new List<DeploymentComplete__e>{
            makeEvent('same-batch-deploy'),
            makeEvent('same-batch-deploy')
        };

        Test.startTest();
        DeploymentCompleteTriggerHandler.handleEvents(events);
        Test.stopTest();

        Integer execCount = [
            SELECT COUNT()
            FROM   SmokeTestExecution__c
            WHERE  DeploymentId__c = 'same-batch-deploy'
        ];
        System.assertEquals(1, execCount,
            'Same DeploymentId appearing twice in one batch should produce exactly 1 execution');

        resetFlags();
    }

    // =========================================================================
    // Test 10 — empty events list is handled gracefully
    // =========================================================================

    @isTest
    static void emptyEventList_noExecution() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        DeploymentCompleteTriggerHandler.shadowModeOverride = false;

        Test.startTest();
        DeploymentCompleteTriggerHandler.handleEvents(new List<DeploymentComplete__e>());
        Test.stopTest();

        Integer execCount = [SELECT COUNT() FROM SmokeTestExecution__c];
        System.assertEquals(0, execCount, 'Empty event list must produce no executions');

        resetFlags();
    }

    // =========================================================================
    // Test 11 — duplicate outside window (>5 min old) does NOT block execution
    // =========================================================================

    @isTest
    static void oldExecution_outsideDedupWindow_allowsNewExecution() {
        SmokeTestOrchestrator.bypassEnqueue = true;
        DeploymentCompleteTriggerHandler.shadowModeOverride = false;

        // Pre-create an execution older than 5 minutes
        insert new SmokeTestExecution__c(
            Status__c        = 'Completed',
            TriggerSource__c = 'Platform Event',
            StartTime__c     = DateTime.now().addMinutes(-10),
            DeploymentId__c  = 'old-deploy-001'
        );

        Test.startTest();
        DeploymentCompleteTriggerHandler.handleEvents(
            new List<DeploymentComplete__e>{ makeEvent('old-deploy-001') }
        );
        Test.stopTest();

        Integer execCount = [
            SELECT COUNT()
            FROM   SmokeTestExecution__c
            WHERE  DeploymentId__c = 'old-deploy-001'
        ];
        System.assertEquals(2, execCount,
            'An execution older than 5 minutes should not block a new execution for the same deployment');

        resetFlags();
    }

    // =========================================================================
    // Test 12 — integration: EventBus.publish triggers execution (via trigger)
    // =========================================================================

    @isTest
    static void eventBusPublish_triggerFiresAndCreatesExecution() {
        SmokeTestOrchestrator.bypassEnqueue         = true;
        DeploymentCompleteTriggerHandler.shadowModeOverride = false;

        DeploymentComplete__e evt = new DeploymentComplete__e(
            DeploymentId__c = 'eventbus-integration-001'
        );

        Test.startTest();
        EventBus.publish(evt);
        Test.stopTest();

        List<SmokeTestExecution__c> execs = [
            SELECT TriggerSource__c, DeploymentId__c
            FROM   SmokeTestExecution__c
            WHERE  DeploymentId__c = 'eventbus-integration-001'
        ];
        System.assertEquals(1, execs.size(),
            'Publishing a DeploymentComplete__e event should fire the trigger and create an execution');
        System.assertEquals('Platform Event', execs[0].TriggerSource__c,
            'TriggerSource must be Platform Event');

        resetFlags();
    }
}
