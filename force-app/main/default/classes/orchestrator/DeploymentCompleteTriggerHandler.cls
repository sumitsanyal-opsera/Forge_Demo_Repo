/**
 * Handles DeploymentComplete__e Platform Event consumption.
 *
 * Each event invocation may carry multiple events (bulk delivery). For each event
 * the handler:
 *   1. Validates DeploymentId__c is not blank
 *   2. Checks for an existing SmokeTestExecution__c with the same DeploymentId
 *      within the last 5 minutes (duplicate detection)
 *   3. If ShadowMode__c is enabled, logs the event and writes an audit record
 *      but does NOT enqueue the orchestrator
 *   4. Otherwise calls SmokeTestOrchestrator.startExecution('Platform Event')
 *      and stores the DeploymentId on the resulting execution record
 *
 * All orchestrator invocations are wrapped in try-catch — the trigger must never
 * propagate exceptions back to the Platform Event bus.
 */
public without sharing class DeploymentCompleteTriggerHandler {

    private static final Integer DEDUP_WINDOW_MINUTES = 5;
    private static final String  TRIGGER_SOURCE        = 'Platform Event';

    // =========================================================================
    // @TestVisible injection
    // =========================================================================

    @TestVisible static IDmlHandler dmlOverride      = null;
    @TestVisible static Boolean     shadowModeOverride = null;

    // =========================================================================
    // Entry point
    // =========================================================================

    public static void handleEvents(List<DeploymentComplete__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        Boolean shadowMode    = resolveShadowMode();
        IDmlHandler dmlHandler = dmlOverride != null ? dmlOverride : new DefaultDmlHandler();
        AuditLogWriter writer  = new AuditLogWriter(dmlHandler);

        // Collect valid DeploymentIds for bulk duplicate detection
        List<DeploymentComplete__e> validEvents = new List<DeploymentComplete__e>();
        Set<String> validDeploymentIds          = new Set<String>();

        for (DeploymentComplete__e evt : events) {
            if (String.isBlank(evt.DeploymentId__c)) {
                System.debug(System.LoggingLevel.WARN,
                    'DeploymentCompleteTriggerHandler: skipping event with null/blank DeploymentId__c');
            } else {
                validEvents.add(evt);
                validDeploymentIds.add(evt.DeploymentId__c);
            }
        }

        if (validEvents.isEmpty()) {
            return;
        }

        // Bulk duplicate check — find any execution for these deployment IDs
        // created within the last DEDUP_WINDOW_MINUTES minutes
        DateTime windowStart = DateTime.now().addMinutes(-DEDUP_WINDOW_MINUTES);
        Set<String> alreadyProcessed = new Set<String>();

        for (SmokeTestExecution__c existing : [
            SELECT DeploymentId__c
            FROM   SmokeTestExecution__c
            WHERE  DeploymentId__c IN :validDeploymentIds
            AND    StartTime__c   >= :windowStart
            LIMIT  200
        ]) {
            alreadyProcessed.add(existing.DeploymentId__c);
        }

        // Track deployment IDs seen within this batch to handle same-batch duplicates
        Set<String> seenThisBatch = new Set<String>();

        for (DeploymentComplete__e evt : validEvents) {
            String deploymentId = evt.DeploymentId__c;

            if (alreadyProcessed.contains(deploymentId) || seenThisBatch.contains(deploymentId)) {
                System.debug(System.LoggingLevel.INFO,
                    'DeploymentCompleteTriggerHandler: duplicate detected for DeploymentId='
                    + deploymentId + ' — skipping execution');
                continue;
            }
            seenThisBatch.add(deploymentId);

            if (shadowMode) {
                System.debug(System.LoggingLevel.INFO,
                    'DeploymentCompleteTriggerHandler: shadow mode active — '
                    + 'logging event receipt for DeploymentId=' + deploymentId
                    + ', orchestrator NOT enqueued');
                try {
                    writer.logAction(
                        new AuditLogEntry.Builder()
                            .actionType(AuditLogEntry.ACTION_TEST_EXECUTION)
                            .resourceType('DeploymentComplete__e')
                            .resourceId(deploymentId)
                            .outcome('SHADOW_MODE_SKIPPED')
                            .changeReason('Shadow mode enabled — event received but execution suppressed')
                            .newValue('TriggerSource=' + TRIGGER_SOURCE
                                + '; DeploymentId=' + deploymentId)
                            .build()
                    );
                } catch (Exception auditEx) {
                    System.debug(System.LoggingLevel.ERROR,
                        'DeploymentCompleteTriggerHandler: failed to write shadow-mode audit record: '
                        + auditEx.getMessage());
                }
                continue;
            }

            // Non-shadow, non-duplicate: start execution
            try {
                Id executionId = SmokeTestOrchestrator.startExecution(TRIGGER_SOURCE);
                if (executionId != null) {
                    SmokeTestExecution__c exec = new SmokeTestExecution__c(
                        Id             = executionId,
                        DeploymentId__c = deploymentId
                    );
                    update exec;
                }
            } catch (Exception e) {
                System.debug(System.LoggingLevel.ERROR,
                    'DeploymentCompleteTriggerHandler: error starting execution for DeploymentId='
                    + deploymentId + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
                try {
                    writer.logAction(
                        new AuditLogEntry.Builder()
                            .actionType(AuditLogEntry.ACTION_TEST_EXECUTION)
                            .resourceType('DeploymentComplete__e')
                            .resourceId(deploymentId)
                            .outcome('ERROR')
                            .newValue('TriggerSource=' + TRIGGER_SOURCE
                                + '; Error=' + e.getMessage())
                            .build()
                    );
                } catch (Exception auditEx) {
                    System.debug(System.LoggingLevel.ERROR,
                        'DeploymentCompleteTriggerHandler: failed to write error audit record: '
                        + auditEx.getMessage());
                }
            }
        }
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private static Boolean resolveShadowMode() {
        if (shadowModeOverride != null) {
            return shadowModeOverride;
        }
        Map<String, SmokeTestConfig__mdt> configs = SmokeTestConfig__mdt.getAll();
        if (configs != null && !configs.isEmpty()) {
            SmokeTestConfig__mdt cfg = configs.values()[0];
            return cfg.ShadowMode__c == true;
        }
        return false;
    }
}
