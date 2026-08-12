/**
 * Immutable value object returned by IAlertChannelAdapter.send().
 * Captures the outcome of a single channel dispatch attempt.
 */
public class AlertResult {

    /** Whether the alert was successfully dispatched through the channel */
    public final Boolean success;

    /** Channel type string matching SmokeTestAlertRoute__mdt.Channel__c: InApp, Email, Slack, Teams */
    public final String channelType;

    /** Number of recipients the alert was dispatched to (0 on failure) */
    public final Integer recipientCount;

    /** Error message if success=false; null on success. PII-sanitized before persistence. */
    public final String errorMessage;

    public AlertResult(Boolean success, String channelType, Integer recipientCount, String errorMessage) {
        this.success        = (success != null) ? success : false;
        this.channelType    = channelType;
        this.recipientCount = (recipientCount != null) ? recipientCount : 0;
        this.errorMessage   = errorMessage;
    }

    public Boolean isSuccess() { return success == true; }

    public override String toString() {
        return 'AlertResult[channel=' + channelType
            + ', success=' + success
            + ', recipients=' + recipientCount
            + (String.isNotBlank(errorMessage) ? ', error=' + errorMessage : '')
            + ']';
    }
}
