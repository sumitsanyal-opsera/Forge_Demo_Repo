/**
 * Typed wrapper for a permission failure detected during role-based scenario execution.
 *
 * Populated by RoleBasedScenarioExecutor when an InsufficientAccessException,
 * NoAccessException, SecurityException, or access-related DmlException is caught
 * inside a System.runAs() block. Contains the parsed details of the missing permission
 * so callers can surface specific, actionable messages (e.g., "Standard User lacks
 * Edit permission on Opportunity.Amount").
 */
public class PermissionFailureDetail {

    /** Salesforce Profile name under which the failure occurred */
    public String profileName;

    /** SObject API name extracted from the exception (e.g., 'Opportunity', 'Account') */
    public String objectName;

    /** Field API name extracted from the exception, or null for object-level failures */
    public String fieldName;

    /** Permission type: one of Read, Edit, Create, Delete, or Unknown */
    public String permissionType;

    /** Exception message after passing through ErrorSanitizer — never contains raw PII */
    public String rawMessage;

    public PermissionFailureDetail() {}

    public PermissionFailureDetail(
        String profileName,
        String objectName,
        String fieldName,
        String permissionType,
        String rawMessage
    ) {
        this.profileName    = profileName;
        this.objectName     = objectName;
        this.fieldName      = fieldName;
        this.permissionType = permissionType;
        this.rawMessage     = rawMessage;
    }

    /**
     * Returns a human-readable summary string for inclusion in SmokeTestResult__c.ErrorMessage__c.
     * Example: "Profile [Standard User] lacks Edit permission on Opportunity.Amount"
     */
    public String toDetailMessage() {
        String base = 'Profile [' + (profileName != null ? profileName : 'Unknown') + '] lacks '
            + (permissionType != null ? permissionType : 'Unknown') + ' permission on '
            + (objectName != null ? objectName : 'Unknown');
        if (String.isNotBlank(fieldName)) {
            base += '.' + fieldName;
        }
        return base;
    }

    public override String toString() {
        return toDetailMessage();
    }
}
