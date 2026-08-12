/**
 * Enforces immutability on SmokeTestAuditLog__c records.
 *
 * All audit log records are write-once: inserts are permitted but updates and
 * deletes are blocked unconditionally, satisfying SOC 2, SOX, and HIPAA
 * requirements. The error is added to each individual record so bulk callers
 * receive per-record failure information rather than a single exception.
 *
 * NOTE: A retention purge bypass via a static Boolean flag is intentionally
 * NOT implemented here — deferred to the retention purge epic per WO-003 spec.
 */
public with sharing class SmokeTestAuditLogTriggerHandler {

    public static final String IMMUTABILITY_ERROR =
        'Audit log records are immutable and cannot be modified or deleted. ' +
        'Contact your Salesforce administrator if you believe this is an error.';

    /**
     * Called from the before update trigger context.
     * Adds the immutability error to every record in the update batch.
     */
    public static void handleBeforeUpdate(List<SmokeTestAuditLog__c> newRecords) {
        for (SmokeTestAuditLog__c record : newRecords) {
            record.addError(IMMUTABILITY_ERROR);
        }
    }

    /**
     * Called from the before delete trigger context.
     * Adds the immutability error to every record in the delete batch.
     */
    public static void handleBeforeDelete(List<SmokeTestAuditLog__c> oldRecords) {
        for (SmokeTestAuditLog__c record : oldRecords) {
            record.addError(IMMUTABILITY_ERROR);
        }
    }
}
