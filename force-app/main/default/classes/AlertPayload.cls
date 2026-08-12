/**
 * Value object carrying all information an alert adapter needs to build and send a notification.
 *
 * Security: securityThresholdBreached is a boolean indicator only — actual score values are
 * NEVER included here (Confidential data classification per PRD data policy).
 *
 * recipientIds is populated by AlertDispatchService before calling adapter.send():
 *   - InApp channel: Salesforce User IDs (15 or 18-char)
 *   - Email channel: Email address strings
 */
public class AlertPayload {

    /** Id of the SmokeTestExecution__c that completed */
    public Id executionId;

    /** Overall suite result: 'Pass', 'Fail', 'Error', 'Partial' */
    public String overallResult;

    /**
     * List of scenario names (ScenarioName__c) that failed in this execution.
     * Used for scenario tag filter matching; must NOT include security score values.
     */
    public List<String> failedScenarioNames;

    /**
     * True if the post-deployment security health score breached the configured threshold.
     * Boolean only — the actual score is never included in alert payloads.
     */
    public Boolean securityThresholdBreached;

    /** When the execution completed (UTC) */
    public Datetime timestamp;

    /** How the execution was triggered: 'API', 'Platform Event', 'Manual', etc. */
    public String triggerSource;

    /**
     * Resolved recipient identifiers for the current route.
     * Set by AlertDispatchService before calling adapter.send() — adapters must not resolve this themselves.
     *   InApp: Salesforce User IDs
     *   Email: Email addresses
     */
    public List<String> recipientIds;

    public AlertPayload() {
        this.failedScenarioNames = new List<String>();
        this.recipientIds        = new List<String>();
        this.securityThresholdBreached = false;
        this.timestamp           = Datetime.now();
    }

    public AlertPayload(
        Id executionId,
        String overallResult,
        List<String> failedScenarioNames,
        Boolean securityThresholdBreached,
        Datetime timestamp,
        String triggerSource
    ) {
        this.executionId              = executionId;
        this.overallResult            = overallResult;
        this.failedScenarioNames      = (failedScenarioNames != null)
            ? failedScenarioNames : new List<String>();
        this.securityThresholdBreached = (securityThresholdBreached != null)
            ? securityThresholdBreached : false;
        this.timestamp                = (timestamp != null) ? timestamp : Datetime.now();
        this.triggerSource            = triggerSource;
        this.recipientIds             = new List<String>();
    }

    /** Returns true when the overall result indicates a failure state */
    public Boolean isFailing() {
        if (String.isBlank(overallResult)) { return false; }
        String lower = overallResult.toLowerCase();
        return lower.equals('fail') || lower.equals('failed') || lower.equals('error');
    }
}
