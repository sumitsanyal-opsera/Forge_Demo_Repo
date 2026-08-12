/**
 * Decorator that wraps ISmokeTestScenario.execute() in a System.runAs() block,
 * enabling role-based smoke test execution to verify that user profiles have the
 * correct permissions after a deployment.
 *
 * System.runAs() is effective only within @isTest context. In production contexts,
 * executeAsProfile() detects the non-test environment and returns an error result
 * rather than throwing, preserving the non-blocking contract of the scenario chain.
 *
 * Usage:
 *   RoleBasedScenarioExecutor exec = new RoleBasedScenarioExecutor();
 *   RoleBasedScenarioExecutor.ScenarioExecutionResult result =
 *       exec.executeAsProfile(new AccountCrudScenario(), 'Standard User', context);
 *
 * Profile name source: SmokeTestScenario__mdt.RoleProfile__c
 * Result persisted to: SmokeTestResult__c with RoleProfile__c set to the profile name
 *
 * Supported permission failure exceptions (detected inside System.runAs()):
 *   - System.NoAccessException     — SOQL WITH SECURITY_ENFORCED / object not accessible
 *   - System.InsufficientAccessException — similar to NoAccessException
 *   - DmlException (access-related) — INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY,
 *                                      ENTITY_PERMISSIONS, INSUFFICIENT_ACCESS_OR_READONLY
 *   - Any other exception           — captured as UNEXPECTED_ERROR, not PERMISSION_DENIED
 */
public with sharing class RoleBasedScenarioExecutor {

    private static final Integer MAX_ERROR_LEN = 1000;

    // =========================================================================
    // ScenarioExecutionResult — typed return value
    // =========================================================================

    public class ScenarioExecutionResult {
        public final ScenarioResult          scenarioResult;
        public final String                  profileName;
        public final PermissionFailureDetail permissionFailureDetail;
        public final Boolean                 profileNotFound;

        private ScenarioExecutionResult(
            ScenarioResult          scenarioResult,
            String                  profileName,
            PermissionFailureDetail permissionFailureDetail,
            Boolean                 profileNotFound
        ) {
            this.scenarioResult         = scenarioResult;
            this.profileName            = profileName;
            this.permissionFailureDetail = permissionFailureDetail;
            this.profileNotFound        = (profileNotFound != null) ? profileNotFound : false;
        }

        public Boolean isPassed() {
            return scenarioResult != null && scenarioResult.passed;
        }

        public Boolean isPermissionFailure() {
            return permissionFailureDetail != null;
        }
    }

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Executes the given scenario under the specified Salesforce Profile using
     * System.runAs(). Creates a temporary test user for the profile; the user is
     * automatically rolled back with the test transaction.
     *
     * @param scenario      ISmokeTestScenario to execute
     * @param profileName   Salesforce Profile Name (e.g. 'Standard User') — trimmed before use
     * @param context       SmokeTestContext carrying the execution ID
     * @return              ScenarioExecutionResult with pass/fail status, profile name,
     *                      and optional PermissionFailureDetail when a permission error is detected
     */
    public ScenarioExecutionResult executeAsProfile(
        ISmokeTestScenario scenario,
        String             profileName,
        SmokeTestContext   context
    ) {
        String scenarioName = scenario.getMetadata().scenarioName;

        // Guard: System.runAs() is a no-op outside @isTest context
        if (!Test.isRunningTest()) {
            return buildErrorResult(
                scenarioName, profileName, 'NOT_TEST_CONTEXT',
                'Role-based execution via System.runAs() is only supported within @isTest context'
            );
        }

        // Trim and validate profile name
        String trimmedProfile = (profileName != null) ? profileName.trim() : '';
        if (String.isBlank(trimmedProfile)) {
            return buildErrorResult(
                scenarioName, profileName, 'INVALID_PROFILE',
                'profileName must not be blank'
            );
        }

        // Profile lookup — defers non-null-safe handling to WOREF-042 but must not throw NPE
        List<Profile> profiles = [
            SELECT Id FROM Profile WHERE Name = :trimmedProfile WITH SECURITY_ENFORCED LIMIT 1
        ];
        if (profiles.isEmpty()) {
            Long elapsed = 0L;
            return new ScenarioExecutionResult(
                ScenarioResult.failure(
                    scenarioName, elapsed, 'PROFILE_NOT_FOUND',
                    'No Profile found with Name: ' + trimmedProfile
                ),
                trimmedProfile,
                null,
                true
            );
        }

        // Create dedicated test user — auto-rolled back with the test transaction
        User testUser;
        try {
            testUser = SmokeTestDataFactory.createUserWithProfile(trimmedProfile);
        } catch (Exception e) {
            return buildErrorResult(
                scenarioName, trimmedProfile, 'USER_CREATION_FAILED',
                'Failed to create test user for profile [' + trimmedProfile + ']: '
                + cap(ErrorSanitizer.sanitize(e.getMessage()))
            );
        }

        // Execute scenario under the test user's profile
        Long startMs = System.currentTimeMillis();
        ScenarioResult          scenarioResult   = null;
        PermissionFailureDetail failureDetail    = null;

        System.runAs(testUser) {
            try {
                scenarioResult = scenario.execute(context);
            } catch (System.NoAccessException e) {
                Long elapsed = System.currentTimeMillis() - startMs;
                failureDetail = parsePermissionFailure(e.getMessage(), trimmedProfile);
                String detail = failureDetail.toDetailMessage()
                    + ' | ' + cap(ErrorSanitizer.sanitize(e.getMessage()));
                scenarioResult = ScenarioResult.failure(
                    scenarioName, elapsed, 'PERMISSION_DENIED', cap(detail)
                );
            } catch (System.InsufficientAccessException e) {
                Long elapsed = System.currentTimeMillis() - startMs;
                failureDetail = parsePermissionFailure(e.getMessage(), trimmedProfile);
                String detail = failureDetail.toDetailMessage()
                    + ' | ' + cap(ErrorSanitizer.sanitize(e.getMessage()));
                scenarioResult = ScenarioResult.failure(
                    scenarioName, elapsed, 'PERMISSION_DENIED', cap(detail)
                );
            } catch (DmlException e) {
                Long elapsed = System.currentTimeMillis() - startMs;
                if (isAccessRelatedDml(e)) {
                    failureDetail = parsePermissionFailure(e.getMessage(), trimmedProfile);
                    String detail = failureDetail.toDetailMessage()
                        + ' | ' + cap(ErrorSanitizer.sanitize(e.getMessage()));
                    scenarioResult = ScenarioResult.failure(
                        scenarioName, elapsed, 'PERMISSION_DENIED', cap(detail)
                    );
                } else {
                    scenarioResult = ScenarioResult.failure(
                        scenarioName, elapsed, 'DML_EXCEPTION',
                        cap(ErrorSanitizer.sanitize(e.getMessage()))
                    );
                }
            } catch (Exception e) {
                Long elapsed = System.currentTimeMillis() - startMs;
                scenarioResult = ScenarioResult.failure(
                    scenarioName, elapsed, 'UNEXPECTED_ERROR',
                    cap(ErrorSanitizer.sanitize(e.getMessage()))
                );
            }
        }

        // If scenario did not set a result (edge case), build a fallback
        if (scenarioResult == null) {
            scenarioResult = ScenarioResult.failure(
                scenarioName, System.currentTimeMillis() - startMs,
                'UNEXPECTED_ERROR', 'Scenario produced no result'
            );
        }

        return new ScenarioExecutionResult(scenarioResult, trimmedProfile, failureDetail, false);
    }

    /**
     * Convenience overload — creates an execution record internally for callers
     * that do not already have a SmokeTestExecution__c.
     */
    public ScenarioExecutionResult executeAsProfile(
        ISmokeTestScenario scenario,
        String             profileName
    ) {
        SmokeTestExecution__c exec = new SmokeTestExecution__c(
            Status__c         = 'In Progress',
            TriggerSource__c  = 'Role-Based Test',
            StartTime__c      = DateTime.now(),
            TotalScenarios__c = 1
        );
        insert exec;
        SmokeTestContext ctx = new SmokeTestContext(exec.Id, null, new Map<String, Object>());
        return executeAsProfile(scenario, profileName, ctx);
    }

    /**
     * Persists a ScenarioExecutionResult to SmokeTestResult__c with RoleProfile__c set.
     *
     * @param result          Result from executeAsProfile()
     * @param executionId     Parent SmokeTestExecution__c.Id
     * @param executionOrder  Position in the scenario execution sequence
     * @return                Inserted SmokeTestResult__c record with Id populated
     */
    public SmokeTestResult__c persistResult(
        ScenarioExecutionResult result,
        Id                      executionId,
        Integer                 executionOrder
    ) {
        if (result == null || result.scenarioResult == null) {
            throw new IllegalArgumentException('result and result.scenarioResult must not be null');
        }

        ScenarioResult sr = result.scenarioResult;
        String resultStatus = sr.passed ? 'Pass' : deriveStatus(sr.errorType);

        String errorMsg = null;
        if (sr.errorType != null || sr.errorDetail != null) {
            errorMsg = (sr.errorType  != null ? '[' + sr.errorType + '] ' : '')
                + (sr.errorDetail != null ? sr.errorDetail : '');
            if (errorMsg.length() > 32000) {
                errorMsg = errorMsg.substring(0, 32000);
            }
        }

        SmokeTestResult__c rec = new SmokeTestResult__c(
            Execution__c        = executionId,
            ScenarioName__c     = sr.scenarioName,
            Status__c           = resultStatus,
            ExecutionTimeMs__c  = sr.durationMs,
            ErrorMessage__c     = errorMsg,
            ExecutionOrder__c   = executionOrder,
            RoleProfile__c      = result.profileName
        );

        try {
            insert rec;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR,
                'RoleBasedScenarioExecutor.persistResult: DML failed: ' + e.getMessage());
        }
        return rec;
    }

    // =========================================================================
    // Permission failure parsing
    // =========================================================================

    /**
     * Parses an exception message to extract permission failure detail.
     * Uses String.contains() checks for common Salesforce permission error patterns.
     */
    @TestVisible
    private static PermissionFailureDetail parsePermissionFailure(String message, String profileName) {
        String safe = (message != null) ? message : '';

        String objectName     = extractObjectName(safe);
        String fieldName      = extractFieldName(safe);
        String permissionType = extractPermissionType(safe);

        return new PermissionFailureDetail(
            profileName,
            objectName,
            fieldName,
            permissionType,
            ErrorSanitizer.sanitize(cap(safe))
        );
    }

    @TestVisible
    static String extractObjectName(String message) {
        if (String.isBlank(message)) { return null; }

        // Pattern: "Entity type 'Account' is not accessible"
        Pattern entityTypePattern = Pattern.compile(
            "(?i)Entity\\s+type\\s+'([A-Za-z0-9_]+)'"
        );
        Matcher m = entityTypePattern.matcher(message);
        if (m.find()) { return m.group(1); }

        // Pattern: "SObject type 'Account' is not supported"
        Pattern sObjectPattern = Pattern.compile(
            "(?i)SObject\\s+type\\s+'([A-Za-z0-9_]+)'"
        );
        m = sObjectPattern.matcher(message);
        if (m.find()) { return m.group(1); }

        // Pattern: object name before '.FieldName__c'
        Pattern fieldPattern = Pattern.compile(
            "(?i)'([A-Za-z0-9_]+)\\.([A-Za-z0-9_]+)'"
        );
        m = fieldPattern.matcher(message);
        if (m.find()) { return m.group(1); }

        return null;
    }

    @TestVisible
    static String extractFieldName(String message) {
        if (String.isBlank(message)) { return null; }

        // Pattern: "field 'Account.Amount__c'" or "'Account.Amount__c'"
        Pattern fieldPattern = Pattern.compile(
            "(?i)'[A-Za-z0-9_]+\\.([A-Za-z0-9_]+)'"
        );
        Matcher m = fieldPattern.matcher(message);
        if (m.find()) { return m.group(1); }

        // Pattern: "field Amount__c is not accessible"
        Pattern simpleField = Pattern.compile(
            "(?i)field\\s+'?([A-Za-z0-9_]+__c)'?\\s+is\\s+not\\s+accessible"
        );
        m = simpleField.matcher(message);
        if (m.find()) { return m.group(1); }

        return null;
    }

    @TestVisible
    static String extractPermissionType(String message) {
        if (String.isBlank(message)) { return 'Unknown'; }
        String lower = message.toLowerCase();

        // Check for explicit operation keywords in order of specificity
        if (lower.contains('(delete)') || lower.contains('delete permission')
                || lower.contains('is not deletable')) {
            return 'Delete';
        }
        if (lower.contains('(create)') || lower.contains('create permission')
                || lower.contains('is not creatable')) {
            return 'Create';
        }
        if (lower.contains('(update)') || lower.contains('(edit)')
                || lower.contains('update permission') || lower.contains('edit permission')
                || lower.contains('is not updatable') || lower.contains('read-only')) {
            return 'Edit';
        }
        if (lower.contains('(read)') || lower.contains('read permission')
                || lower.contains('is not readable') || lower.contains('not accessible')) {
            return 'Read';
        }
        if (lower.contains('insert')) { return 'Create'; }
        if (lower.contains('update') || lower.contains('edit')) { return 'Edit'; }
        if (lower.contains('delete')) { return 'Delete'; }
        if (lower.contains('read')   || lower.contains('access')) { return 'Read'; }
        return 'Unknown';
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private static Boolean isAccessRelatedDml(DmlException e) {
        String msg = (e.getMessage() != null) ? e.getMessage().toLowerCase() : '';
        return msg.contains('insufficient access')
            || msg.contains('not accessible')
            || msg.contains('entity_permissions')
            || msg.contains('field_permissions')
            || msg.contains('insufficient_access_on_cross_reference_entity')
            || msg.contains('insufficient_access_or_readonly')
            || msg.contains('read-only')
            || msg.contains('access restricted');
    }

    private static ScenarioExecutionResult buildErrorResult(
        String scenarioName,
        String profileName,
        String errorType,
        String errorDetail
    ) {
        return new ScenarioExecutionResult(
            ScenarioResult.failure(scenarioName, 0L, errorType, errorDetail),
            profileName,
            null,
            false
        );
    }

    private static String deriveStatus(String errorType) {
        if (errorType == null)                   { return 'Fail'; }
        if (errorType == 'TIMED_OUT')            { return 'Timeout'; }
        if (errorType.startsWith('SKIPPED_'))    { return 'Skipped'; }
        return 'Fail';
    }

    private static String cap(String s) {
        if (s == null) { return null; }
        return s.length() > MAX_ERROR_LEN ? s.substring(0, MAX_ERROR_LEN) : s;
    }
}
