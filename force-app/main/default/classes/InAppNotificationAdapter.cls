/**
 * IAlertChannelAdapter implementation for Salesforce in-app bell notifications.
 *
 * Uses Messaging.CustomNotification with the 'SmokeTest_Alert' CustomNotificationType.
 * If the CustomNotificationType does not exist in the target org, returns a failure result
 * without throwing — the missing type is a configuration gap, not a code error.
 *
 * Security: alert body contains threshold status indicators only — no score values.
 */
public with sharing class InAppNotificationAdapter implements IAlertChannelAdapter {

    private static final String CHANNEL_TYPE       = 'InApp';
    private static final String NOTIF_TYPE_NAME    = 'SmokeTest_Alert';
    private static final Integer MAX_BODY_LEN      = 750;

    /** Inject a pre-queried CustomNotificationType Id for unit testing */
    @TestVisible static String injectedNotifTypeId = null;

    // =========================================================================
    // IAlertChannelAdapter
    // =========================================================================

    public String getChannelType() { return CHANNEL_TYPE; }

    public AlertResult send(AlertPayload payload) {
        if (payload == null || payload.recipientIds == null || payload.recipientIds.isEmpty()) {
            return new AlertResult(false, CHANNEL_TYPE, 0, 'No recipient IDs provided');
        }

        // Resolve CustomNotificationType Id
        String notifTypeId = injectedNotifTypeId;
        if (String.isBlank(notifTypeId)) {
            try {
                notifTypeId = resolveNotifTypeId();
            } catch (Exception ex) {
                return new AlertResult(
                    false, CHANNEL_TYPE, 0,
                    'CustomNotificationType lookup failed: ' + ex.getMessage()
                );
            }
        }
        if (String.isBlank(notifTypeId)) {
            return new AlertResult(
                false, CHANNEL_TYPE, 0,
                'CustomNotificationType "' + NOTIF_TYPE_NAME + '" not found in this org. '
                + 'Deploy the notification type metadata before using InApp alerts.'
            );
        }

        String title = buildTitle(payload);
        String body  = buildBody(payload);

        Set<String> recipientSet = new Set<String>(payload.recipientIds);

        try {
            Messaging.CustomNotification notif = new Messaging.CustomNotification();
            notif.setNotificationTypeId(notifTypeId);
            notif.setTitle(title);
            notif.setBody(body);
            // Target the smoke test execution record as the notification anchor
            if (payload.executionId != null) {
                notif.setTargetId(payload.executionId);
            }
            notif.send(recipientSet);
            return new AlertResult(true, CHANNEL_TYPE, recipientSet.size(), null);
        } catch (Exception ex) {
            return new AlertResult(
                false, CHANNEL_TYPE, 0,
                ErrorSanitizer.sanitize(ex.getMessage())
            );
        }
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private static String resolveNotifTypeId() {
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType
            WHERE DeveloperName = :NOTIF_TYPE_NAME
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }

    private static String buildTitle(AlertPayload payload) {
        String result = String.isNotBlank(payload.overallResult)
            ? payload.overallResult : 'Unknown';
        return 'Smoke Test: ' + result;
    }

    private static String buildBody(AlertPayload payload) {
        List<String> parts = new List<String>();

        if (payload.failedScenarioNames != null && !payload.failedScenarioNames.isEmpty()) {
            parts.add('Failed: ' + String.join(payload.failedScenarioNames, ', '));
        }

        if (payload.securityThresholdBreached == true) {
            parts.add('Security score below threshold.');
        }

        if (String.isNotBlank(payload.triggerSource)) {
            parts.add('Trigger: ' + payload.triggerSource);
        }

        String body = parts.isEmpty()
            ? 'Execution ' + payload.executionId + ' completed.'
            : String.join(parts, ' | ');

        return body.length() > MAX_BODY_LEN ? body.substring(0, MAX_BODY_LEN) : body;
    }
}
