/**
 * Core alert dispatching service that routes smoke test completion alerts to configured
 * notification channels based on SmokeTestAlertRoute__mdt routing rules.
 *
 * Routing logic:
 *   1. Load all SmokeTestAlertRoute__mdt records where Enabled__c = true
 *   2. Filter each route by AlertOnFail__c / AlertOnPass__c against the execution result
 *   3. If ScenarioFilter__c is set, match comma-separated tags against failed scenario names
 *   4. Resolve recipients via PermissionSetAssignment for the route's RecipientRole__c
 *   5. Dispatch through the registered IAlertChannelAdapter for the route's Channel__c
 *   6. Write an immutable SmokeTestAuditLog__c record for every dispatch attempt
 *
 * Isolation: individual adapter failures do not block other routes — each call is independently
 * try-caught and logged. Audit records are created even for failed dispatches.
 *
 * Security: security score numeric values are NEVER passed to adapters — only the boolean
 * securityThresholdBreached indicator from AlertPayload (Confidential data classification).
 */
public with sharing class AlertDispatchService {

    // PermissionSet name lookup keyed by RecipientRole__c value from SmokeTestAlertRoute__mdt
    @TestVisible
    private static final Map<String, String> ROLE_TO_PERM_SET = new Map<String, String>{
        'System Administrator' => 'SmokeTest_Admin',
        'Team Lead'            => 'SmokeTest_Admin',
        'Business Owner'       => 'SmokeTest_Dashboard_Viewer',
        'QA Engineer'          => 'SmokeTest_Dashboard_Viewer',
        'DevOps Engineer'      => 'SmokeTest_API_User'
    };

    // Injectable CMT route list for unit testing (getAll() unavailable in test without SeeAllData)
    @TestVisible static List<SmokeTestAlertRoute__mdt> injectedRoutes = null;

    private final Map<String, IAlertChannelAdapter> adapters;
    private final AuditLogWriter                    auditWriter;

    /**
     * Production constructor — uses the default InApp and Email adapters.
     * Additional channel adapters (Slack, Teams) are registered in future WOs.
     */
    public AlertDispatchService() {
        this(buildDefaultAdapters(), new AuditLogWriter(new DefaultDmlHandler()));
    }

    /**
     * Dependency-injection constructor for unit testing.
     *
     * @param adapters     Map of Channel__c value → adapter instance (e.g. 'InApp' → MockAdapter)
     * @param auditWriter  AuditLogWriter instance (inject a mock handler for tests)
     */
    public AlertDispatchService(
        Map<String, IAlertChannelAdapter> adapters,
        AuditLogWriter auditWriter
    ) {
        this.adapters    = (adapters    != null) ? adapters    : buildDefaultAdapters();
        this.auditWriter = (auditWriter != null) ? auditWriter : new AuditLogWriter(new DefaultDmlHandler());
    }

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Evaluates all enabled alert routes against the payload and dispatches notifications.
     *
     * @param payload  Alert content — must not contain security score numeric values
     * @return         List of AlertResult, one per route evaluated; empty if no routes matched
     */
    public List<AlertResult> dispatch(AlertPayload payload) {
        if (payload == null) {
            throw new IllegalArgumentException('payload must not be null');
        }

        List<SmokeTestAlertRoute__mdt> matchedRoutes = getMatchedRoutes(payload);

        if (matchedRoutes.isEmpty()) {
            logNoMatchAudit(payload);
            return new List<AlertResult>();
        }

        List<AlertResult> results = new List<AlertResult>();
        for (SmokeTestAlertRoute__mdt route : matchedRoutes) {
            AlertResult result = dispatchSingleRoute(route, payload);
            results.add(result);
        }
        return results;
    }

    // =========================================================================
    // Route filtering
    // =========================================================================

    private List<SmokeTestAlertRoute__mdt> getMatchedRoutes(AlertPayload payload) {
        Map<String, SmokeTestAlertRoute__mdt> allRoutes;
        if (injectedRoutes != null) {
            allRoutes = new Map<String, SmokeTestAlertRoute__mdt>();
            for (SmokeTestAlertRoute__mdt r : injectedRoutes) {
                allRoutes.put(r.DeveloperName, r);
            }
        } else {
            allRoutes = SmokeTestAlertRoute__mdt.getAll();
        }

        List<SmokeTestAlertRoute__mdt> matched = new List<SmokeTestAlertRoute__mdt>();
        for (SmokeTestAlertRoute__mdt route : allRoutes.values()) {
            if (!isRouteApplicable(route, payload)) { continue; }
            matched.add(route);
        }
        return matched;
    }

    private static Boolean isRouteApplicable(SmokeTestAlertRoute__mdt route, AlertPayload payload) {
        // Only enabled routes
        if (route.Enabled__c != true) { return false; }

        // AlertOnFail / AlertOnPass gating
        Boolean isFailing = payload.isFailing();
        if (isFailing  && route.AlertOnFail__c != true) { return false; }
        if (!isFailing && route.AlertOnPass__c != true) { return false; }

        // ScenarioFilter__c: comma-separated cloud/business-process tags; empty = match all
        if (String.isNotBlank(route.ScenarioFilter__c)
                && !matchesScenarioFilter(route.ScenarioFilter__c, payload)) {
            return false;
        }

        return true;
    }

    private static Boolean matchesScenarioFilter(String filterStr, AlertPayload payload) {
        Set<String> filterTags = new Set<String>();
        for (String tag : filterStr.split(',')) {
            filterTags.add(tag.trim().toLowerCase());
        }

        // Match against failed scenario names (direct or via CMT BusinessProcess__c lookup)
        if (payload.failedScenarioNames != null) {
            for (String name : payload.failedScenarioNames) {
                if (filterTags.contains(name.toLowerCase())) { return true; }
            }
        }

        // Match against scenario BusinessProcess__c via CMT lookup (no SOQL limit cost)
        Map<String, SmokeTestScenario__mdt> scenarioCmt = SmokeTestScenario__mdt.getAll();
        if (payload.failedScenarioNames != null) {
            for (String scenarioName : payload.failedScenarioNames) {
                SmokeTestScenario__mdt scenMdt = scenarioCmt.get(scenarioName);
                if (scenMdt != null
                        && String.isNotBlank(scenMdt.BusinessProcess__c)
                        && filterTags.contains(scenMdt.BusinessProcess__c.toLowerCase())) {
                    return true;
                }
            }
        }

        // Also match triggerSource against tags
        if (String.isNotBlank(payload.triggerSource)
                && filterTags.contains(payload.triggerSource.toLowerCase())) {
            return true;
        }

        return false;
    }

    // =========================================================================
    // Single route dispatch
    // =========================================================================

    private AlertResult dispatchSingleRoute(SmokeTestAlertRoute__mdt route, AlertPayload payload) {
        String channelType = route.Channel__c;

        // Look up adapter
        IAlertChannelAdapter adapter = adapters.get(channelType);
        if (adapter == null) {
            AlertResult noAdapter = new AlertResult(
                false, channelType, 0,
                'No adapter registered for channel type: ' + channelType
            );
            writeDispatchAudit(payload, route, noAdapter);
            return noAdapter;
        }

        // Resolve recipients
        List<String> recipientIds;
        try {
            recipientIds = resolveRecipients(route.RecipientRole__c, channelType);
        } catch (Exception ex) {
            AlertResult recipErr = new AlertResult(
                false, channelType, 0,
                'Recipient resolution failed for role [' + route.RecipientRole__c + ']: '
                    + ErrorSanitizer.sanitize(ex.getMessage())
            );
            writeDispatchAudit(payload, route, recipErr);
            return recipErr;
        }

        if (recipientIds.isEmpty()) {
            AlertResult noRecip = new AlertResult(
                false, channelType, 0,
                'No active recipients found for role: ' + route.RecipientRole__c
                    + '. Verify permission set assignment.'
            );
            writeDispatchAudit(payload, route, noRecip);
            return noRecip;
        }

        // Clone the payload so each route gets its own recipient list
        AlertPayload routePayload = clonePayload(payload);
        routePayload.recipientIds = recipientIds;

        // Dispatch — individual adapter failures must not block other routes
        AlertResult result;
        try {
            result = adapter.send(routePayload);
            if (result == null) {
                result = new AlertResult(false, channelType, 0, 'Adapter returned null result');
            }
        } catch (Exception ex) {
            result = new AlertResult(
                false, channelType, 0,
                ErrorSanitizer.sanitize(ex.getMessage())
            );
        }

        writeDispatchAudit(payload, route, result);
        return result;
    }

    // =========================================================================
    // Recipient resolution
    // =========================================================================

    /**
     * Resolves RecipientRole__c to a list of user identifiers appropriate for the channel.
     * InApp: returns User IDs; Email: returns email address strings.
     */
    @TestVisible
    static List<String> resolveRecipients(String recipientRole, String channelType) {
        if (String.isBlank(recipientRole)) { return new List<String>(); }

        String psName = ROLE_TO_PERM_SET.containsKey(recipientRole)
            ? ROLE_TO_PERM_SET.get(recipientRole)
            : recipientRole;  // fallback: role IS the permission set name

        List<String> results = new List<String>();

        if (channelType == 'InApp') {
            for (PermissionSetAssignment psa : [
                SELECT AssigneeId
                FROM   PermissionSetAssignment
                WHERE  PermissionSet.Name = :psName
                   AND Assignee.IsActive  = true
                WITH SECURITY_ENFORCED
            ]) {
                results.add(psa.AssigneeId);
            }
        } else if (channelType == 'Email') {
            for (PermissionSetAssignment psa : [
                SELECT Assignee.Email
                FROM   PermissionSetAssignment
                WHERE  PermissionSet.Name = :psName
                   AND Assignee.IsActive  = true
                WITH SECURITY_ENFORCED
            ]) {
                if (String.isNotBlank(psa.Assignee.Email)) {
                    results.add(psa.Assignee.Email);
                }
            }
        }

        return results;
    }

    // =========================================================================
    // Audit logging
    // =========================================================================

    private void logNoMatchAudit(AlertPayload payload) {
        try {
            auditWriter.logAction(
                new AuditLogEntry.Builder()
                    .actionType(AuditLogEntry.ACTION_ALERT_SENT)
                    .resourceType('AlertDispatch')
                    .resourceId(String.valueOf(payload.executionId))
                    .newValue('No enabled routes matched for result: ' + payload.overallResult)
                    .outcome('Skipped')
                    .executionId(payload.executionId)
                    .build()
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'AlertDispatchService: audit log failed: ' + ex.getMessage());
        }
    }

    private void writeDispatchAudit(
        AlertPayload payload,
        SmokeTestAlertRoute__mdt route,
        AlertResult result
    ) {
        try {
            String detail = JSON.serialize(new Map<String, Object>{
                'channelType'    => result.channelType,
                'recipientCount' => result.recipientCount,
                'success'        => result.success,
                'route'          => route.DeveloperName,
                'errorMessage'   => result.errorMessage
            });
            auditWriter.logAction(
                new AuditLogEntry.Builder()
                    .actionType(AuditLogEntry.ACTION_ALERT_SENT)
                    .resourceType('AlertDispatch')
                    .resourceId(String.valueOf(payload.executionId))
                    .newValue(detail)
                    .outcome(result.success ? 'Success' : 'Failure')
                    .executionId(payload.executionId)
                    .build()
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'AlertDispatchService: dispatch audit failed for route '
                + route.DeveloperName + ': ' + ex.getMessage());
        }
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private static AlertPayload clonePayload(AlertPayload src) {
        AlertPayload copy = new AlertPayload(
            src.executionId,
            src.overallResult,
            src.failedScenarioNames,
            src.securityThresholdBreached,
            src.timestamp,
            src.triggerSource
        );
        return copy;
    }

    private static Map<String, IAlertChannelAdapter> buildDefaultAdapters() {
        Map<String, IAlertChannelAdapter> map = new Map<String, IAlertChannelAdapter>();
        map.put('InApp', new InAppNotificationAdapter());
        map.put('Email', new EmailAlertAdapter());
        return map;
    }
}
