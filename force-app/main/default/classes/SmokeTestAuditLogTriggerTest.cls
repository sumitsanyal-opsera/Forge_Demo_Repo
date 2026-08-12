@isTest
private class SmokeTestAuditLogTriggerTest {

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    private static SmokeTestAuditLog__c buildAuditLog(String action) {
        return new SmokeTestAuditLog__c(
            Action__c     = action,
            Actor__c      = UserInfo.getUserId(),
            Timestamp__c  = System.now(),
            ResourceType__c = 'SmokeTestExecution__c',
            ResourceId__c   = 'EXEC-0001',
            ReferenceId__c  = 'test-ref-001'
        );
    }

    // -----------------------------------------------------------------------
    // Test: insert succeeds — immutability only blocks update/delete
    // -----------------------------------------------------------------------
    @isTest
    static void testInsertSucceeds() {
        SmokeTestAuditLog__c log = buildAuditLog('Execution Started');

        Test.startTest();
        insert log;
        Test.stopTest();

        SmokeTestAuditLog__c queried = [
            SELECT Id, Action__c, Actor__c, Timestamp__c, ResourceType__c
            FROM SmokeTestAuditLog__c
            WHERE Id = :log.Id
        ];
        System.assertNotEquals(null, queried.Id, 'Insert should succeed');
        System.assertEquals('Execution Started', queried.Action__c, 'Action should be persisted');
        System.assertEquals(UserInfo.getUserId(), queried.Actor__c, 'Actor should be persisted');
    }

    // -----------------------------------------------------------------------
    // Test: update is blocked with the immutability error message
    // -----------------------------------------------------------------------
    @isTest
    static void testUpdateBlocked() {
        SmokeTestAuditLog__c log = buildAuditLog('Config Changed');
        insert log;

        log.ResourceId__c = 'MODIFIED-VALUE';

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            update log;
        } catch (DmlException e) {
            exceptionThrown = true;
            System.assert(
                e.getMessage().contains('immutable'),
                'Exception message should contain "immutable": ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Update should throw DmlException');
    }

    // -----------------------------------------------------------------------
    // Test: delete is blocked with the immutability error message
    // -----------------------------------------------------------------------
    @isTest
    static void testDeleteBlocked() {
        SmokeTestAuditLog__c log = buildAuditLog('Alert Sent');
        insert log;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            delete log;
        } catch (DmlException e) {
            exceptionThrown = true;
            System.assert(
                e.getMessage().contains('immutable'),
                'Exception message should contain "immutable": ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Delete should throw DmlException');

        // Confirm the record was NOT deleted
        List<SmokeTestAuditLog__c> remaining = [
            SELECT Id FROM SmokeTestAuditLog__c WHERE Id = :log.Id
        ];
        System.assertEquals(1, remaining.size(), 'Record should still exist after blocked delete');
    }

    // -----------------------------------------------------------------------
    // Test: bulk update (200 records) is blocked — all records get the error
    // -----------------------------------------------------------------------
    @isTest
    static void testBulkUpdateBlocked() {
        List<SmokeTestAuditLog__c> logs = new List<SmokeTestAuditLog__c>();
        for (Integer i = 0; i < 200; i++) {
            logs.add(buildAuditLog('Execution Completed'));
        }
        insert logs;

        // Mutate all records
        for (SmokeTestAuditLog__c log : logs) {
            log.ResourceId__c = 'BULK-MODIFIED';
        }

        Test.startTest();
        Database.SaveResult[] results = Database.update(logs, false);
        Test.stopTest();

        Integer errorCount = 0;
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                errorCount++;
                System.assert(
                    sr.getErrors()[0].getMessage().contains('immutable'),
                    'Each error should contain "immutable": ' + sr.getErrors()[0].getMessage()
                );
            }
        }
        System.assertEquals(200, errorCount, 'All 200 records should fail the update');
    }
}
