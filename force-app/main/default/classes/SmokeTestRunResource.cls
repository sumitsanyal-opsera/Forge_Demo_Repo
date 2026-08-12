/**
 * REST endpoint: POST /services/apexrest/smoketest/v1/run
 *
 * Primary CI/CD integration point for triggering post-deployment smoke test
 * execution. Validates input, checks authorization and queue capacity, creates
 * the SmokeTestExecution__c record, enqueues the SmokeTestOrchestrator, and
 * returns HTTP 202 with an executionId within 2 seconds P95.
 *
 * Request body (JSON):
 *   { targetOrg: String (required),
 *     scenarioFilter: String[] (optional),
 *     webhookCallbackUrl: String (optional, HTTPS, must match allow-list),
 *     rollbackPolicyOverride: String (optional),
 *     timeout: Integer (optional, 60-600) }
 *
 * Responses:
 *   202 { executionId, status: 'queued', timestamp }
 *   400 VALIDATION_ERROR
 *   403 FORBIDDEN (missing permission set)
 *   429 RATE_LIMITED (queue capacity exceeded) + Retry-After header
 *   500 INTERNAL_ERROR
 */
@RestResource(urlMapping='/smoketest/v1/run')
global with sharing class SmokeTestRunResource {

    // =========================================================================
    // Constants
    // =========================================================================

    private static final Integer DEFAULT_RETRY_AFTER_SEC = 30;
    private static final Integer FLEX_QUEUE_MAX          = 250;
    private static final Integer DEFAULT_QUEUE_DEPTH_PCT = 80;
    private static final Integer DEFAULT_TIMEOUT_SEC     = 300;

    // =========================================================================
    // @TestVisible injection flags
    // =========================================================================

    /** Override the async job count for queue-depth tests without inserting real jobs. */
    @TestVisible static Integer asyncJobCountOverride = null;

    // =========================================================================
    // @HttpPost — POST /smoketest/v1/run
    // =========================================================================

    @HttpPost
    global static void doPost() {
        String jsonBody = RestContext.request.requestBody != null
            ? RestContext.request.requestBody.toString()
            : null;

        // 1. Validate input
        SmokeTestApiValidator.ValidationResult vr =
            SmokeTestApiValidator.validateRunRequest(jsonBody);
        if (!vr.isValid) {
            SmokeTestApiResponse.error400()
                .withErrorCode('VALIDATION_ERROR')
                .withMessage(String.join(vr.errors, '; '))
                .send();
            return;
        }

        // 2. Permission set authorization
        if (!hasPermission()) {
            SmokeTestApiResponse.error403()
                .withErrorCode('FORBIDDEN')
                .withMessage(
                    'User lacks SmokeTest_API_User or SmokeTest_Admin permission set')
                .send();
            return;
        }

        // 3. Rate limiting — async queue depth check
        if (isQueueCapacityExceeded()) {
            SmokeTestApiResponse.error429()
                .withErrorCode('RATE_LIMITED')
                .withMessage(
                    'Async queue capacity exceeded. Retry after '
                    + DEFAULT_RETRY_AFTER_SEC + ' seconds.')
                .withRetryAfter(DEFAULT_RETRY_AFTER_SEC)
                .send();
            return;
        }

        Map<String,Object> parsed = vr.parsedRequest;
        String targetOrg      = String.valueOf(parsed.get('targetOrg'));
        String webhookUrl     = parsed.containsKey('webhookCallbackUrl')
            ? String.valueOf(parsed.get('webhookCallbackUrl')) : null;
        String rollbackPolicy = parsed.containsKey('rollbackPolicyOverride')
            ? String.valueOf(parsed.get('rollbackPolicyOverride')) : null;

        try {
            // 4. Load scenarios and suite configuration
            DateTime startTime = DateTime.now();
            ScenarioDispatcher dispatcher = new ScenarioDispatcher();
            List<ScenarioDispatcher.ScenarioConfig> scenarios =
                dispatcher.getEnabledScenarios();
            Integer timeoutSec = loadSuiteTimeoutSec();

            // 5. Create execution record with Status='Queued'
            SmokeTestExecution__c exec = new SmokeTestExecution__c(
                Status__c             = 'Queued',
                TriggerSource__c      = 'API',
                StartTime__c          = startTime,
                InitiatedBy__c        = UserInfo.getUserId(),
                TargetOrg__c          = targetOrg,
                WebhookCallbackUrl__c = webhookUrl,
                RollbackPolicy__c     = rollbackPolicy,
                TotalScenarios__c     = scenarios.size()
            );
            insert exec;

            // 6. Enqueue orchestrator (skip when no scenarios to avoid index error)
            if (!scenarios.isEmpty()) {
                try {
                    System.enqueueJob(new SmokeTestOrchestrator(
                        exec.Id, scenarios, 0, dispatcher, 'API', startTime, timeoutSec
                    ));
                } catch (Exception enqueueEx) {
                    System.debug(LoggingLevel.ERROR,
                        'SmokeTestRunResource: failed to enqueue orchestrator for execution '
                        + exec.Id + ': ' + enqueueEx.getMessage());
                    writeAuditLog(exec.Id, targetOrg, 'ENQUEUE_ERROR');
                    SmokeTestApiResponse.error500()
                        .withErrorCode('INTERNAL_ERROR')
                        .withMessage('Failed to enqueue smoke test job')
                        .send();
                    return;
                }
            }

            // 7. Write audit log
            writeAuditLog(exec.Id, targetOrg, 'SUCCESS');

            // 8. Return 202 Accepted
            sendAccepted(exec.Id);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestRunResource: unexpected error: ' + e.getMessage()
                + '\n' + e.getStackTraceString());
            writeAuditLog(null, targetOrg, 'ERROR');
            SmokeTestApiResponse.error500()
                .withErrorCode('INTERNAL_ERROR')
                .withMessage('An unexpected error occurred')
                .send();
        }
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private static Boolean hasPermission() {
        Integer count = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND   PermissionSet.Name IN ('SmokeTest_API_User', 'SmokeTest_Admin')
            WITH SECURITY_ENFORCED
        ];
        return count > 0;
    }

    private static Boolean isQueueCapacityExceeded() {
        Integer thresholdPct = loadQueueDepthPct();
        Integer limit = (Integer) Math.floor(thresholdPct / 100.0 * FLEX_QUEUE_MAX);

        Integer activeCount = asyncJobCountOverride != null
            ? asyncJobCountOverride
            : [SELECT COUNT() FROM AsyncApexJob
               WHERE Status IN ('Queued', 'Preparing', 'Processing')];

        return activeCount >= limit;
    }

    private static Integer loadSuiteTimeoutSec() {
        try {
            List<SmokeTestConfig__mdt> cfgs = [
                SELECT SuiteTimeoutSec__c
                FROM   SmokeTestConfig__mdt
                WHERE  DeveloperName = 'Default'
                WITH SECURITY_ENFORCED
                LIMIT  1
            ];
            if (!cfgs.isEmpty() && cfgs[0].SuiteTimeoutSec__c != null) {
                return Integer.valueOf(cfgs[0].SuiteTimeoutSec__c);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'SmokeTestRunResource: could not load SuiteTimeoutSec__c: '
                + e.getMessage());
        }
        return DEFAULT_TIMEOUT_SEC;
    }

    private static Integer loadQueueDepthPct() {
        try {
            List<SmokeTestConfig__mdt> cfgs = [
                SELECT BackpressureQueueDepthPct__c
                FROM   SmokeTestConfig__mdt
                WHERE  DeveloperName = 'Default'
                WITH SECURITY_ENFORCED
                LIMIT  1
            ];
            if (!cfgs.isEmpty() && cfgs[0].BackpressureQueueDepthPct__c != null) {
                return Integer.valueOf(cfgs[0].BackpressureQueueDepthPct__c);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'SmokeTestRunResource: could not load BackpressureQueueDepthPct__c: '
                + e.getMessage());
        }
        return DEFAULT_QUEUE_DEPTH_PCT;
    }

    private static void writeAuditLog(Id executionId, String targetOrg, String outcome) {
        try {
            AuditLogEntry.Builder builder = new AuditLogEntry.Builder()
                .actionType(AuditLogEntry.ACTION_TEST_EXECUTION)
                .resourceType('SmokeTestExecution__c')
                .outcome(outcome)
                .newValue(
                    'TriggerSource=API; TargetOrg='
                    + (targetOrg != null ? targetOrg : 'unknown'));
            if (executionId != null) {
                builder.resourceId(String.valueOf(executionId));
                builder.executionId(executionId);
            }
            AuditLogWriter writer = new AuditLogWriter(new DefaultDmlHandler());
            writer.logAction(builder.build());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestRunResource: failed to write audit log: ' + e.getMessage());
        }
    }

    private static void sendAccepted(Id executionId) {
        SmokeTestApiResponse.RunAcknowledgment ack =
            new SmokeTestApiResponse.RunAcknowledgment(String.valueOf(executionId), 'queued');
        RestContext.response.statusCode = 202;
        RestContext.response.addHeader('Content-Type', 'application/json;charset=UTF-8');
        RestContext.response.addHeader('X-API-Version', 'v1');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(ack));
    }
}
