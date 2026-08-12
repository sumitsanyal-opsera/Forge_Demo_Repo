/**
 * IAlertChannelAdapter implementation for Salesforce Email Service alerts.
 *
 * Uses Messaging.SingleEmailMessage. Email sends are batched in groups of 10 per
 * Messaging.sendEmail() call to respect the 10-email-per-invocation governor limit
 * that applies to non-system email operations.
 *
 * OrgWideEmailAddress: queries for the first available org-wide email address and uses it
 * as the sender; falls back to current-user address if none is configured.
 *
 * Security: email body contains threshold status indicators only — no score values.
 */
public with sharing class EmailAlertAdapter implements IAlertChannelAdapter {

    private static final String  CHANNEL_TYPE   = 'Email';
    private static final Integer BATCH_SIZE      = 10;  // Salesforce single-transaction email limit
    private static final Integer MAX_BODY_LEN    = 4000;
    private static final String  EMAIL_SUBJECT   = 'Smoke Test Alert: ';

    // =========================================================================
    // IAlertChannelAdapter
    // =========================================================================

    public String getChannelType() { return CHANNEL_TYPE; }

    public AlertResult send(AlertPayload payload) {
        if (payload == null || payload.recipientIds == null || payload.recipientIds.isEmpty()) {
            return new AlertResult(false, CHANNEL_TYPE, 0, 'No recipient email addresses provided');
        }

        String subject     = buildSubject(payload);
        String htmlBody    = buildHtmlBody(payload);
        String orgWideId   = resolveOrgWideEmailId();

        Integer totalSent  = 0;
        String  lastError  = null;

        // Batch in groups of BATCH_SIZE to respect email governor limit
        Integer total = payload.recipientIds.size();
        Integer sent  = 0;

        while (sent < total) {
            Integer batchEnd = Math.min(sent + BATCH_SIZE, total);
            List<String> batchAddresses = new List<String>();
            for (Integer i = sent; i < batchEnd; i++) {
                if (String.isNotBlank(payload.recipientIds[i])) {
                    batchAddresses.add(payload.recipientIds[i]);
                }
            }
            sent = batchEnd;

            if (batchAddresses.isEmpty()) { continue; }

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(batchAddresses);
            email.setSubject(subject);
            email.setHtmlBody(htmlBody);
            email.setSaveAsActivity(false);

            if (String.isNotBlank(orgWideId)) {
                email.setOrgWideEmailAddressId(orgWideId);
            }

            try {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage>{ email },
                    false  // allOrNone=false: partial send rather than all-or-nothing
                );
                for (Messaging.SendEmailResult r : results) {
                    if (r.isSuccess()) {
                        totalSent += batchAddresses.size();
                    } else {
                        for (Messaging.SendEmailError err : r.getErrors()) {
                            lastError = err.getMessage();
                        }
                    }
                }
            } catch (Exception ex) {
                lastError = ErrorSanitizer.sanitize(ex.getMessage());
            }
        }

        Boolean success = (totalSent > 0);
        return new AlertResult(success, CHANNEL_TYPE, totalSent,
            success ? null : (String.isNotBlank(lastError) ? lastError : 'No emails sent successfully'));
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private static String buildSubject(AlertPayload payload) {
        String result = String.isNotBlank(payload.overallResult)
            ? payload.overallResult : 'Unknown';
        return EMAIL_SUBJECT + result;
    }

    private static String buildHtmlBody(AlertPayload payload) {
        List<String> lines = new List<String>();
        lines.add('<p><strong>Smoke Test Execution Result: '
            + escapeHtml(payload.overallResult) + '</strong></p>');

        if (payload.executionId != null) {
            lines.add('<p>Execution ID: ' + escapeHtml(String.valueOf(payload.executionId)) + '</p>');
        }

        if (payload.triggerSource != null) {
            lines.add('<p>Trigger: ' + escapeHtml(payload.triggerSource) + '</p>');
        }

        if (payload.failedScenarioNames != null && !payload.failedScenarioNames.isEmpty()) {
            lines.add('<p><strong>Failed Scenarios:</strong></p><ul>');
            for (String name : payload.failedScenarioNames) {
                lines.add('<li>' + escapeHtml(name) + '</li>');
            }
            lines.add('</ul>');
        }

        if (payload.securityThresholdBreached == true) {
            lines.add('<p><strong>Security:</strong> Score is below the configured threshold. '
                + 'Please review security health settings.</p>');
        }

        if (payload.timestamp != null) {
            lines.add('<p>Timestamp: '
                + escapeHtml(payload.timestamp.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''))
                + '</p>');
        }

        String body = String.join(lines, '\n');
        return body.length() > MAX_BODY_LEN ? body.substring(0, MAX_BODY_LEN) : body;
    }

    private static String resolveOrgWideEmailId() {
        try {
            List<OrgWideEmailAddress> owa = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE IsAllowAllProfiles = true
                LIMIT 1
            ];
            return owa.isEmpty() ? null : owa[0].Id;
        } catch (Exception ex) {
            return null;
        }
    }

    private static String escapeHtml(String s) {
        if (s == null) { return ''; }
        return s.replace('&', '&amp;')
                .replace('<', '&lt;')
                .replace('>', '&gt;')
                .replace('"', '&quot;');
    }
}
