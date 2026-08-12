/**
 * Anonymous Apex script to verify SmokeTestAuditLog__c immutability enforcement.
 * Run via: sf apex run --file scripts/verify-audit-immutability.apex --target-org <alias>
 *
 * Verifies:
 * - Insert succeeds
 * - Update is blocked with the immutability error message
 * - Delete is blocked with the immutability error message
 */

// --- Step 1: Insert a valid audit log record (should succeed) ---
SmokeTestAuditLog__c auditLog = new SmokeTestAuditLog__c(
    Action__c       = 'Execution Started',
    Actor__c        = UserInfo.getUserId(),
    Timestamp__c    = System.now(),
    ResourceType__c = 'SmokeTestExecution__c',
    ResourceId__c   = 'EXEC-0001',
    ReferenceId__c  = 'verify-script-001',
    IPAddress__c    = '127.0.0.1'
);
insert auditLog;
System.debug('SUCCESS: Inserted audit log record: ' + auditLog.Id + ' (' + auditLog.Name + ')');

// --- Step 2: Attempt update (should be blocked) ---
auditLog.ResourceId__c = 'TAMPERED-VALUE';
Boolean updateBlocked = false;
try {
    update auditLog;
    System.debug('FAILURE: Update succeeded — immutability trigger is NOT working!');
} catch (DmlException e) {
    updateBlocked = true;
    System.debug('SUCCESS: Update blocked with error: ' + e.getDmlMessage(0));
    System.assert(
        e.getDmlMessage(0).contains('immutable'),
        'Expected immutability error message, got: ' + e.getDmlMessage(0)
    );
}
System.assert(updateBlocked, 'Update must be blocked');

// --- Step 3: Confirm record was not modified ---
SmokeTestAuditLog__c requeried = [
    SELECT ResourceId__c FROM SmokeTestAuditLog__c WHERE Id = :auditLog.Id
];
System.assert(
    requeried.ResourceId__c == 'EXEC-0001',
    'Record should retain original value, got: ' + requeried.ResourceId__c
);
System.debug('SUCCESS: Record value unchanged after blocked update.');

// --- Step 4: Attempt delete (should be blocked) ---
Boolean deleteBlocked = false;
try {
    delete auditLog;
    System.debug('FAILURE: Delete succeeded — immutability trigger is NOT working!');
} catch (DmlException e) {
    deleteBlocked = true;
    System.debug('SUCCESS: Delete blocked with error: ' + e.getDmlMessage(0));
}
System.assert(deleteBlocked, 'Delete must be blocked');

// --- Step 5: Confirm record still exists ---
List<SmokeTestAuditLog__c> remaining = [SELECT Id FROM SmokeTestAuditLog__c WHERE Id = :auditLog.Id];
System.assert(remaining.size() == 1, 'Record should still exist after blocked delete');
System.debug('SUCCESS: Record still exists after blocked delete.');

System.debug('=== Audit immutability verification PASSED ===');
