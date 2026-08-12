/**
 * Pluggable adapter interface for alert notification channels.
 * Implementations: InAppNotificationAdapter, EmailAlertAdapter.
 * Additional channels (Slack, Teams) implement this interface in future WOs.
 */
public interface IAlertChannelAdapter {

    /**
     * Sends an alert through this channel to the recipients specified in payload.recipientIds.
     *
     * @param payload  Alert content and recipient list; recipientIds is set by AlertDispatchService
     *                 before this call (user IDs for InApp, email addresses for Email)
     * @return         AlertResult indicating success/failure, recipient count, and any error message
     */
    AlertResult send(AlertPayload payload);

    /**
     * @return  The channel type string matching SmokeTestAlertRoute__mdt.Channel__c
     *          e.g. 'InApp', 'Email', 'Slack', 'Teams'
     */
    String getChannelType();
}
