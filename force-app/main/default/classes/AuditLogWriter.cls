/**
 * Centralized, immutable audit logging service for SmokeTestAuditLog__c.
 *
 * Design decisions:
 *   - without sharing: runs in system context so any calling transaction can write
 *     audit records regardless of the running user's permission set assignment.
 *     SmokeTest_Admin permission set controls who can READ audit records.
 *   - Dependency injection via IDmlHandler: unit tests supply a mock handler;
 *     production callers use new AuditLogWriter(new DefaultDmlHandler()).
 *   - Timestamp is always server-side (Datetime.now()) — never caller-supplied.
 *   - Null actorUserId defaults to UserInfo.getUserId() with a debug warning.
 *   - LongTextArea values truncated at LONG_TEXT_MAX chars with [TRUNCATED] suffix.
 *   - If fewer than 2 DML statements remain in the transaction, the write is
 *     queued asynchronously via AuditLogAsyncWriter (inner Queueable class).
 */
public without sharing class AuditLogWriter {

    @TestVisible private static final Integer LONG_TEXT_MAX    = 32000;
    @TestVisible private static final String  TRUNCATED_SUFFIX = '[TRUNCATED]';

    // Set to true in tests to force the async code path without consuming 149 DML statements
    @TestVisible private static Boolean forceAsync = false;

    private IDmlHandler dml;

    public AuditLogWriter(IDmlHandler dml) {
        if (dml == null) {
            throw new AuditLogEntry.AuditLogException('IDmlHandler must not be null');
        }
        this.dml = dml;
    }

    // =========================================================================
    // Public API
    // =========================================================================

    public void logAction(AuditLogEntry entry) {
        logActions(new List<AuditLogEntry>{ entry });
    }

    public void logActions(List<AuditLogEntry> entries) {
        if (entries == null || entries.isEmpty()) {
            return;
        }

        Datetime now = Datetime.now();
        List<SmokeTestAuditLog__c> records = new List<SmokeTestAuditLog__c>();

        for (AuditLogEntry entry : entries) {
            if (entry == null) {
                continue;
            }

            String actorId = entry.getActorUserId();
            if (String.isBlank(actorId)) {
                actorId = UserInfo.getUserId();
                System.debug(LoggingLevel.WARN,
                    'AuditLogWriter: actorUserId was null/blank — defaulting to running user ' + actorId);
            }

            records.add(new SmokeTestAuditLog__c(
                ActorUserId__c  = actorId,
                ActionType__c   = entry.getActionType(),
                Timestamp__c    = now,
                ResourceId__c   = entry.getResourceId(),
                ResourceType__c = entry.getResourceType(),
                OldValue__c     = truncate(entry.getOldValue()),
                NewValue__c     = truncate(entry.getNewValue()),
                ChangeReason__c = entry.getChangeReason(),
                Outcome__c      = entry.getOutcome(),
                IPAddress__c    = entry.getIpAddress(),
                Execution__c    = entry.getExecutionId()
            ));
        }

        if (records.isEmpty()) {
            return;
        }

        if (isDmlBudgetExhausted()) {
            System.debug(LoggingLevel.WARN,
                'AuditLogWriter: DML budget near exhaustion — queuing ' +
                records.size() + ' record(s) for async insertion');
            System.enqueueJob(new AuditLogAsyncWriter(records));
            return;
        }

        try {
            dml.insertRecords(records);
        } catch (Exception e) {
            throw new AuditLogEntry.AuditLogException(
                'AuditLogWriter failed to insert ' + records.size() +
                ' record(s). ActionType=' + entries[0].getActionType() +
                '. Cause: ' + e.getMessage(),
                e
            );
        }
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    @TestVisible
    private static String truncate(String value) {
        if (value == null) {
            return null;
        }
        if (value.length() <= LONG_TEXT_MAX) {
            return value;
        }
        return value.substring(0, LONG_TEXT_MAX - TRUNCATED_SUFFIX.length()) + TRUNCATED_SUFFIX;
    }

    @TestVisible
    private static Boolean isDmlBudgetExhausted() {
        if (forceAsync) {
            return true;
        }
        return (Limits.getLimitDmlStatements() - Limits.getDmlStatements()) < 2;
    }

    // =========================================================================
    // Async fallback for DML budget exhaustion
    // =========================================================================

    public class AuditLogAsyncWriter implements Queueable {
        private List<SmokeTestAuditLog__c> records;

        public AuditLogAsyncWriter(List<SmokeTestAuditLog__c> records) {
            this.records = records;
        }

        public void execute(QueueableContext ctx) {
            Database.insert(records, true);
        }
    }
}
