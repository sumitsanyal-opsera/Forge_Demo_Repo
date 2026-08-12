/**
 * REST endpoint: GET /services/apexrest/smoketest/v1/status/{executionId}
 *
 * Provides real-time execution status for CI/CD polling. Returns current
 * execution state, per-scenario results for completed scenarios, pending
 * indicators for remaining scenarios, and elapsed time.
 *
 * Response (200):
 *   { executionId, status (queued/in_progress/complete/failed),
 *     scenarios: [{ name, result, durationMs, errorDetail }],
 *     executionDurationMs, timestamp }
 *
 * Error responses:
 *   400 VALIDATION_ERROR  — invalid executionId format
 *   403 FORBIDDEN         — missing SmokeTest_API_User or SmokeTest_Admin
 *   404 NOT_FOUND         — executionId not found
 *   500 INTERNAL_ERROR    — query exception or unexpected error
 */
@RestResource(urlMapping='/smoketest/v1/status/*')
global with sharing class SmokeTestStatusResource {

    // =========================================================================
    // @TestVisible injection flags
    // =========================================================================

    /** Override permission check result; null = real check. */
    @TestVisible static Boolean permissionCheckOverride = null;

    // =========================================================================
    // @HttpGet — GET /smoketest/v1/status/{executionId}
    // =========================================================================

    @HttpGet
    global static void doGet() {
        // 1. Extract executionId from URL (last path segment)
        String requestUri = RestContext.request.requestURI;
        String[] segments = requestUri.split('/');
        String executionId = segments[segments.size() - 1];

        // 2. Validate executionId format
        SmokeTestApiValidator.ValidationResult vr =
            SmokeTestApiValidator.validateExecutionId(executionId);
        if (!vr.isValid) {
            SmokeTestApiResponse.error400()
                .withErrorCode('VALIDATION_ERROR')
                .withMessage(String.join(vr.errors, '; '))
                .send();
            return;
        }

        // 3. Permission set authorization
        if (!hasPermission()) {
            SmokeTestApiResponse.error403()
                .withErrorCode('FORBIDDEN')
                .withMessage(
                    'User lacks SmokeTest_API_User or SmokeTest_Admin permission set')
                .send();
            return;
        }

        try {
            // 4. Query execution record (SOQL 1 of 2)
            List<SmokeTestExecution__c> execRows = [
                SELECT Id, Status__c, StartTime__c, EndTime__c, ExecutionTimeMs__c,
                       TotalScenarios__c, PassedScenarios__c, FailedScenarios__c
                FROM SmokeTestExecution__c
                WHERE Id = :executionId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (execRows.isEmpty()) {
                writeAuditLog(executionId, 'NOT_FOUND');
                SmokeTestApiResponse.error404()
                    .withErrorCode('NOT_FOUND')
                    .withMessage('Execution not found')
                    .send();
                return;
            }

            SmokeTestExecution__c exec = execRows[0];

            // 5. Query result records (SOQL 2 of 2)
            List<SmokeTestResult__c> resultRows = [
                SELECT ScenarioName__c, Status__c, ExecutionTimeMs__c,
                       ErrorMessage__c, ExecutionOrder__c
                FROM SmokeTestResult__c
                WHERE Execution__c = :exec.Id
                WITH SECURITY_ENFORCED
                ORDER BY ExecutionOrder__c ASC NULLS LAST
            ];

            // 6. Build scenarios array: completed results + pending placeholders
            List<Map<String, Object>> scenariosList = new List<Map<String, Object>>();
            for (SmokeTestResult__c r : resultRows) {
                Map<String, Object> s = new Map<String, Object>{
                    'name'       => r.ScenarioName__c,
                    'result'     => r.Status__c != null ? r.Status__c.toLowerCase() : 'unknown',
                    'durationMs' => r.ExecutionTimeMs__c != null ? (Long) r.ExecutionTimeMs__c : null,
                    'errorDetail'=> r.ErrorMessage__c
                };
                scenariosList.add(s);
            }

            Integer totalScenarios = exec.TotalScenarios__c != null
                ? (Integer) exec.TotalScenarios__c : 0;
            Integer pendingCount = Math.max(0, totalScenarios - resultRows.size());
            for (Integer i = 0; i < pendingCount; i++) {
                scenariosList.add(new Map<String, Object>{
                    'name'       => null,
                    'result'     => 'pending',
                    'durationMs' => null,
                    'errorDetail'=> null
                });
            }

            // 7. Calculate executionDurationMs
            String execStatus = exec.Status__c;
            Boolean isTerminal = execStatus == 'Completed'
                              || execStatus == 'Failed'
                              || execStatus == 'Aborted';
            Long executionDurationMs;
            if (isTerminal && exec.ExecutionTimeMs__c != null) {
                executionDurationMs = (Long) exec.ExecutionTimeMs__c;
            } else if (exec.StartTime__c != null) {
                executionDurationMs = DateTime.now().getTime() - exec.StartTime__c.getTime();
            } else {
                executionDurationMs = 0L;
            }

            // 8. Build and send response
            Map<String, Object> responseBody = new Map<String, Object>{
                'executionId'        => String.valueOf(exec.Id),
                'status'             => normalizeStatus(execStatus),
                'scenarios'          => scenariosList,
                'executionDurationMs'=> executionDurationMs,
                'timestamp'          => Datetime.now().formatGmt(
                                           'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
            };

            SmokeTestApiResponse.success200().withBody(responseBody).send();

        } catch (QueryException qe) {
            writeAuditLog(executionId, 'QUERY_ERROR');
            SmokeTestApiResponse.error500()
                .withErrorCode('INTERNAL_ERROR')
                .withMessage('Query failed: insufficient access or internal error')
                .send();
        } catch (Exception e) {
            writeAuditLog(executionId, 'ERROR');
            System.debug(LoggingLevel.ERROR,
                'SmokeTestStatusResource: unexpected error: ' + e.getMessage());
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
        if (permissionCheckOverride != null) {
            return permissionCheckOverride;
        }
        Integer count = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND   PermissionSet.Name IN ('SmokeTest_API_User', 'SmokeTest_Admin')
            WITH SECURITY_ENFORCED
        ];
        return count > 0;
    }

    private static String normalizeStatus(String salesforceStatus) {
        if (salesforceStatus == null)          { return 'unknown'; }
        if (salesforceStatus == 'Queued')      { return 'queued'; }
        if (salesforceStatus == 'In Progress') { return 'in_progress'; }
        if (salesforceStatus == 'Completed')   { return 'complete'; }
        if (salesforceStatus == 'Failed')      { return 'failed'; }
        if (salesforceStatus == 'Aborted')     { return 'failed'; }
        return salesforceStatus.toLowerCase().replace(' ', '_');
    }

    private static void writeAuditLog(String executionId, String outcome) {
        try {
            AuditLogEntry.Builder builder = new AuditLogEntry.Builder()
                .actionType(AuditLogEntry.ACTION_TEST_EXECUTION)
                .resourceType('SmokeTestExecution__c')
                .outcome(outcome);
            if (String.isNotBlank(executionId)) {
                builder.resourceId(executionId);
            }
            new AuditLogWriter(new DefaultDmlHandler()).logAction(builder.build());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestStatusResource: failed to write audit log: ' + e.getMessage());
        }
    }
}
