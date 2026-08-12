/**
 * Structured parameter object for AuditLogWriter.logAction().
 * Constructed exclusively via the inner Builder class; constructor is private.
 *
 * Validation is performed in Builder.build():
 *   - actionType must be non-blank and in VALID_ACTION_TYPES
 *   - changeReason is required when actionType is CONFIGURATION_CHANGE
 *   - null actorUserId is allowed here — AuditLogWriter defaults it to the running user
 */
public with sharing class AuditLogEntry {

    // =========================================================================
    // Action type constants
    // =========================================================================

    public static final String ACTION_TEST_EXECUTION   = 'TEST_EXECUTION';
    public static final String ACTION_CONFIG_CHANGE    = 'CONFIGURATION_CHANGE';
    public static final String ACTION_ROLLBACK         = 'ROLLBACK_ACTION';
    public static final String ACTION_ALERT_SENT       = 'ALERT_SENT';
    public static final String ACTION_DASHBOARD_ACCESS = 'DASHBOARD_ACCESS';

    public static final Set<String> VALID_ACTION_TYPES = new Set<String>{
        ACTION_TEST_EXECUTION,
        ACTION_CONFIG_CHANGE,
        ACTION_ROLLBACK,
        ACTION_ALERT_SENT,
        ACTION_DASHBOARD_ACCESS
    };

    // =========================================================================
    // Exception type
    // =========================================================================

    public class AuditLogException extends Exception {}

    // =========================================================================
    // Fields (accessible by AuditLogWriter in the same package)
    // =========================================================================

    @TestVisible private String actorUserId;
    @TestVisible private String actionType;
    @TestVisible private String resourceId;
    @TestVisible private String resourceType;
    @TestVisible private String oldValue;
    @TestVisible private String newValue;
    @TestVisible private String changeReason;
    @TestVisible private String outcome;
    @TestVisible private String ipAddress;
    @TestVisible private Id     executionId;

    private AuditLogEntry() {}

    // =========================================================================
    // Getters
    // =========================================================================

    public String getActorUserId()  { return actorUserId; }
    public String getActionType()   { return actionType; }
    public String getResourceId()   { return resourceId; }
    public String getResourceType() { return resourceType; }
    public String getOldValue()     { return oldValue; }
    public String getNewValue()     { return newValue; }
    public String getChangeReason() { return changeReason; }
    public String getOutcome()      { return outcome; }
    public String getIpAddress()    { return ipAddress; }
    public Id     getExecutionId()  { return executionId; }

    // =========================================================================
    // Builder
    // =========================================================================

    public class Builder {
        private AuditLogEntry e = new AuditLogEntry();

        public Builder actorUserId(String v)  { e.actorUserId  = v; return this; }
        public Builder actionType(String v)   { e.actionType   = v; return this; }
        public Builder resourceId(String v)   { e.resourceId   = v; return this; }
        public Builder resourceType(String v) { e.resourceType = v; return this; }
        public Builder oldValue(String v)     { e.oldValue     = v; return this; }
        public Builder newValue(String v)     { e.newValue     = v; return this; }
        public Builder changeReason(String v) { e.changeReason = v; return this; }
        public Builder outcome(String v)      { e.outcome      = v; return this; }
        public Builder ipAddress(String v)    { e.ipAddress    = v; return this; }
        public Builder executionId(Id v)      { e.executionId  = v; return this; }

        public AuditLogEntry build() {
            if (String.isBlank(e.actionType)) {
                throw new AuditLogException(
                    'ActionType is required. Valid values: ' +
                    String.join(new List<String>(VALID_ACTION_TYPES), ', '));
            }
            if (!VALID_ACTION_TYPES.contains(e.actionType)) {
                throw new AuditLogException(
                    'Invalid ActionType: "' + e.actionType + '". Valid values: ' +
                    String.join(new List<String>(VALID_ACTION_TYPES), ', '));
            }
            if (ACTION_CONFIG_CHANGE.equals(e.actionType) && String.isBlank(e.changeReason)) {
                throw new AuditLogException(
                    'ChangeReason is required when ActionType is CONFIGURATION_CHANGE');
            }
            return e;
        }
    }
}
