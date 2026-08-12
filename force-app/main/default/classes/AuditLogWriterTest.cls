/**
 * Unit and integration tests for AuditLogWriter.
 *
 * Test categories:
 *   Action types         (5)  — one for each supported action type
 *   Bulk insert          (1)  — list overload
 *   Validation failures  (4)  — blank actionType, invalid actionType, missing changeReason,
 *                               null handler
 *   Default behaviours   (2)  — null actorUserId defaults, server-side timestamp
 *   Truncation           (2)  — OldValue > 32000 chars, NewValue > 32000 chars
 *   Async fallback       (1)  — DML budget exhaustion queues async job
 *   DI verification      (1)  — mock DML handler captures calls without database
 *   Integration          (1)  — real record queryable with correct field values
 *   Permission check     (1)  — runAs unprivileged user cannot read audit log
 */
@isTest
private class AuditLogWriterTest {

    // =========================================================================
    // Mock DML handler — captures calls, no database interaction
    // =========================================================================

    private class MockDmlHandler implements IDmlHandler {
        public List<SObject> insertedSingles  = new List<SObject>();
        public List<SObject> insertedBulk     = new List<SObject>();
        public Boolean shouldThrow            = false;

        public void insertRecord(SObject record) {
            if (shouldThrow) throw new DmlException('Mock DML failure');
            insertedSingles.add(record);
        }

        public void insertRecords(List<SObject> records) {
            if (shouldThrow) throw new DmlException('Mock DML failure');
            insertedBulk.addAll(records);
        }
    }

    // =========================================================================
    // Action type tests — one per supported type
    // =========================================================================

    @isTest
    static void testLogActionTestExecution() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);
        AuditLogEntry entry = AuditLogTestDataFactory.createTestExecutionEntry();

        Test.startTest();
        writer.logAction(entry);
        Test.stopTest();

        System.assertEquals(1, mock.insertedBulk.size(), 'Exactly one record should be inserted');
        SmokeTestAuditLog__c rec = (SmokeTestAuditLog__c) mock.insertedBulk[0];
        System.assertEquals(AuditLogEntry.ACTION_TEST_EXECUTION, rec.ActionType__c,
            'ActionType should be TEST_EXECUTION');
        System.assertEquals('success', rec.Outcome__c, 'Outcome should match');
        System.assert(rec.Timestamp__c != null, 'Timestamp must be set server-side');
    }

    @isTest
    static void testLogActionConfigChange() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);
        AuditLogEntry entry = AuditLogTestDataFactory.createConfigChangeEntry();

        Test.startTest();
        writer.logAction(entry);
        Test.stopTest();

        SmokeTestAuditLog__c rec = (SmokeTestAuditLog__c) mock.insertedBulk[0];
        System.assertEquals(AuditLogEntry.ACTION_CONFIG_CHANGE, rec.ActionType__c);
        System.assert(String.isNotBlank(rec.ChangeReason__c),
            'ChangeReason must be populated for CONFIGURATION_CHANGE');
        System.assert(String.isNotBlank(rec.OldValue__c), 'OldValue must be present');
        System.assert(String.isNotBlank(rec.NewValue__c), 'NewValue must be present');
    }

    @isTest
    static void testLogActionRollback() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);

        Test.startTest();
        writer.logAction(AuditLogTestDataFactory.createRollbackEntry());
        Test.stopTest();

        SmokeTestAuditLog__c rec = (SmokeTestAuditLog__c) mock.insertedBulk[0];
        System.assertEquals(AuditLogEntry.ACTION_ROLLBACK, rec.ActionType__c);
        System.assertEquals('success', rec.Outcome__c);
    }

    @isTest
    static void testLogActionAlertSent() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);

        Test.startTest();
        writer.logAction(AuditLogTestDataFactory.createAlertSentEntry());
        Test.stopTest();

        SmokeTestAuditLog__c rec = (SmokeTestAuditLog__c) mock.insertedBulk[0];
        System.assertEquals(AuditLogEntry.ACTION_ALERT_SENT, rec.ActionType__c);
    }

    @isTest
    static void testLogActionDashboardAccess() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);

        Test.startTest();
        writer.logAction(AuditLogTestDataFactory.createDashboardAccessEntry());
        Test.stopTest();

        SmokeTestAuditLog__c rec = (SmokeTestAuditLog__c) mock.insertedBulk[0];
        System.assertEquals(AuditLogEntry.ACTION_DASHBOARD_ACCESS, rec.ActionType__c);
    }

    // =========================================================================
    // Bulk insert
    // =========================================================================

    @isTest
    static void testLogActionsBulk() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);

        List<AuditLogEntry> entries = new List<AuditLogEntry>{
            AuditLogTestDataFactory.createTestExecutionEntry(),
            AuditLogTestDataFactory.createAlertSentEntry(),
            AuditLogTestDataFactory.createDashboardAccessEntry()
        };

        Test.startTest();
        writer.logActions(entries);
        Test.stopTest();

        System.assertEquals(3, mock.insertedBulk.size(),
            'All three entries should be inserted in one bulk call');
    }

    // =========================================================================
    // Validation failures
    // =========================================================================

    @isTest
    static void testBlankActionTypeThrows() {
        AuditLogEntry.AuditLogException thrown;
        Test.startTest();
        try {
            new AuditLogEntry.Builder()
                .actorUserId(UserInfo.getUserId())
                .actionType('')
                .build();
        } catch (AuditLogEntry.AuditLogException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null, 'Should throw AuditLogException for blank actionType');
        System.assert(thrown.getMessage().contains('ActionType is required'),
            'Exception should describe the required field');
    }

    @isTest
    static void testInvalidActionTypeThrows() {
        AuditLogEntry.AuditLogException thrown;
        Test.startTest();
        try {
            new AuditLogEntry.Builder()
                .actorUserId(UserInfo.getUserId())
                .actionType('INVALID_UNKNOWN_TYPE')
                .build();
        } catch (AuditLogEntry.AuditLogException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null, 'Should throw for invalid actionType');
        System.assert(thrown.getMessage().contains('INVALID_UNKNOWN_TYPE'),
            'Exception message should include the invalid value');
    }

    @isTest
    static void testConfigChangeMissingChangeReasonThrows() {
        AuditLogEntry.AuditLogException thrown;
        Test.startTest();
        try {
            new AuditLogEntry.Builder()
                .actorUserId(UserInfo.getUserId())
                .actionType(AuditLogEntry.ACTION_CONFIG_CHANGE)
                .resourceId('SmokeTestConfig__mdt.Default')
                .resourceType('SmokeTestConfig__mdt')
                .build(); // no changeReason
        } catch (AuditLogEntry.AuditLogException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null,
            'Should throw AuditLogException when changeReason is absent for CONFIGURATION_CHANGE');
        System.assert(thrown.getMessage().contains('ChangeReason'),
            'Exception message should mention ChangeReason');
        System.assert(thrown.getMessage().contains('CONFIGURATION_CHANGE'),
            'Exception message should mention the action type');
    }

    @isTest
    static void testNullDmlHandlerThrows() {
        AuditLogEntry.AuditLogException thrown;
        Test.startTest();
        try {
            new AuditLogWriter(null);
        } catch (AuditLogEntry.AuditLogException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null, 'Null IDmlHandler should throw AuditLogException');
    }

    // =========================================================================
    // Default behaviours
    // =========================================================================

    @isTest
    static void testNullActorUserIdDefaultsToRunningUser() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);

        // Build entry WITHOUT setting actorUserId
        AuditLogEntry entry = new AuditLogEntry.Builder()
            .actionType(AuditLogEntry.ACTION_DASHBOARD_ACCESS)
            .resourceType('SmokeTestCenter')
            .outcome('success')
            .build();

        Test.startTest();
        writer.logAction(entry);
        Test.stopTest();

        SmokeTestAuditLog__c rec = (SmokeTestAuditLog__c) mock.insertedBulk[0];
        System.assertEquals(UserInfo.getUserId(), rec.ActorUserId__c,
            'Null actorUserId must default to the running user ID');
    }

    @isTest
    static void testTimestampIsSetServerSide() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);

        Datetime before = Datetime.now();

        Test.startTest();
        writer.logAction(AuditLogTestDataFactory.createTestExecutionEntry());
        Test.stopTest();

        Datetime after = Datetime.now();
        SmokeTestAuditLog__c rec = (SmokeTestAuditLog__c) mock.insertedBulk[0];

        System.assert(rec.Timestamp__c != null, 'Timestamp must not be null');
        System.assert(!rec.Timestamp__c.isBefore(before) || rec.Timestamp__c == before,
            'Server-side timestamp must be at or after the call time');
    }

    // =========================================================================
    // Truncation
    // =========================================================================

    @isTest
    static void testOldValueTruncatedAt32000() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);

        String oversized = 'X'.repeat(33000);
        AuditLogEntry entry = new AuditLogEntry.Builder()
            .actorUserId(UserInfo.getUserId())
            .actionType(AuditLogEntry.ACTION_CONFIG_CHANGE)
            .resourceType('SmokeTestConfig__mdt')
            .oldValue(oversized)
            .newValue('{}')
            .changeReason('Truncation test')
            .build();

        Test.startTest();
        writer.logAction(entry);
        Test.stopTest();

        SmokeTestAuditLog__c rec = (SmokeTestAuditLog__c) mock.insertedBulk[0];
        System.assert(rec.OldValue__c.length() <= 32000,
            'OldValue must be truncated to 32000 chars');
        System.assert(rec.OldValue__c.endsWith('[TRUNCATED]'),
            'Truncated OldValue must end with [TRUNCATED] suffix');
    }

    @isTest
    static void testNewValueTruncatedAt32000() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);

        String oversized = 'Y'.repeat(33000);
        AuditLogEntry entry = new AuditLogEntry.Builder()
            .actorUserId(UserInfo.getUserId())
            .actionType(AuditLogEntry.ACTION_CONFIG_CHANGE)
            .resourceType('SmokeTestConfig__mdt')
            .oldValue('{}')
            .newValue(oversized)
            .changeReason('Truncation test')
            .build();

        Test.startTest();
        writer.logAction(entry);
        Test.stopTest();

        SmokeTestAuditLog__c rec = (SmokeTestAuditLog__c) mock.insertedBulk[0];
        System.assert(rec.NewValue__c.length() <= 32000,
            'NewValue must be truncated to 32000 chars');
        System.assert(rec.NewValue__c.endsWith('[TRUNCATED]'),
            'Truncated NewValue must end with [TRUNCATED] suffix');
    }

    // =========================================================================
    // Async fallback
    // =========================================================================

    @isTest
    static void testDmlBudgetExhaustedUsesAsyncFallback() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);

        // Force async mode via testVisible flag
        AuditLogWriter.forceAsync = true;

        Test.startTest();
        writer.logAction(AuditLogTestDataFactory.createAlertSentEntry());
        Test.stopTest();

        // The mock handler should NOT have been called — async path bypasses it
        System.assertEquals(0, mock.insertedBulk.size(),
            'Mock handler must not be called when async fallback is active');
        // Test.stopTest() flushes async jobs; no exception = async job enqueued successfully
    }

    // =========================================================================
    // DML exception wrapped in AuditLogException
    // =========================================================================

    @isTest
    static void testDmlExceptionIsWrapped() {
        MockDmlHandler mock = new MockDmlHandler();
        mock.shouldThrow = true;
        AuditLogWriter writer = new AuditLogWriter(mock);

        AuditLogEntry.AuditLogException thrown;
        Test.startTest();
        try {
            writer.logAction(AuditLogTestDataFactory.createTestExecutionEntry());
        } catch (AuditLogEntry.AuditLogException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assert(thrown != null,
            'DML failure must be wrapped in AuditLogEntry.AuditLogException');
        System.assert(thrown.getMessage().contains('AuditLogWriter failed'),
            'Wrapped exception message should describe the failure context');
    }

    // =========================================================================
    // Dependency injection verification
    // =========================================================================

    @isTest
    static void testMockHandlerReceivesCorrectRecord() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);

        String resourceId   = 'SmokeTestConfig__mdt.Default';
        String resourceType = 'SmokeTestConfig__mdt';
        String outcome      = 'success';

        AuditLogEntry entry = new AuditLogEntry.Builder()
            .actorUserId(UserInfo.getUserId())
            .actionType(AuditLogEntry.ACTION_CONFIG_CHANGE)
            .resourceId(resourceId)
            .resourceType(resourceType)
            .oldValue('{"val":1}')
            .newValue('{"val":2}')
            .changeReason('DI test')
            .outcome(outcome)
            .build();

        Test.startTest();
        writer.logAction(entry);
        Test.stopTest();

        System.assertEquals(1, mock.insertedBulk.size(), 'Exactly one record passed to DML handler');
        SmokeTestAuditLog__c rec = (SmokeTestAuditLog__c) mock.insertedBulk[0];
        System.assertEquals(AuditLogEntry.ACTION_CONFIG_CHANGE, rec.ActionType__c);
        System.assertEquals(resourceId,   rec.ResourceId__c);
        System.assertEquals(resourceType, rec.ResourceType__c);
        System.assertEquals(outcome,      rec.Outcome__c);
        System.assertEquals('DI test',    rec.ChangeReason__c);
        System.assert(rec.Timestamp__c != null, 'Server-side timestamp must be set');
    }

    // =========================================================================
    // Integration test — real DML, queries record back
    // =========================================================================

    @isTest
    static void testRealInsertAndQueryBack() {
        AuditLogWriter writer = new AuditLogWriter(new DefaultDmlHandler());
        AuditLogEntry entry = AuditLogTestDataFactory.createTestExecutionEntry();

        Test.startTest();
        writer.logAction(entry);
        Test.stopTest();

        List<SmokeTestAuditLog__c> records = [
            SELECT Id, ActionType__c, Outcome__c, ActorUserId__c, Timestamp__c
            FROM SmokeTestAuditLog__c
            WHERE ActionType__c = :AuditLogEntry.ACTION_TEST_EXECUTION
            LIMIT 1
        ];

        System.assertEquals(1, records.size(), 'Audit record must be queryable after insertion');
        System.assertEquals(AuditLogEntry.ACTION_TEST_EXECUTION, records[0].ActionType__c);
        System.assertEquals('success', records[0].Outcome__c);
        System.assert(records[0].Timestamp__c != null, 'Timestamp must be persisted');
    }

    // =========================================================================
    // Permission check — unprivileged user cannot read audit log with SECURITY_ENFORCED
    // =========================================================================

    @isTest
    static void testUnprivilegedUserCannotReadAuditLog() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        Long ts = DateTime.now().getTime();
        User unprivileged = new User(
            FirstName='Audit', LastName='ReadTest',
            Email='audit.readtest@example.test',
            Username='audit.readtest.' + ts + '@example.test',
            Alias='artest', ProfileId=p.Id,
            TimeZoneSidKey='America/New_York', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US'
        );
        insert unprivileged;

        // First insert a record as the system user (no sharing restrictions)
        AuditLogWriter writer = new AuditLogWriter(new DefaultDmlHandler());
        writer.logAction(AuditLogTestDataFactory.createAlertSentEntry());

        System.runAs(unprivileged) {
            Boolean exceptionThrown = false;
            try {
                List<SmokeTestAuditLog__c> records = [
                    SELECT Id FROM SmokeTestAuditLog__c WITH SECURITY_ENFORCED LIMIT 1
                ];
            } catch (Exception e) {
                exceptionThrown = true;
            }
            System.assert(exceptionThrown,
                'Unprivileged user must not read SmokeTestAuditLog__c with SECURITY_ENFORCED');
        }
    }

    // =========================================================================
    // Edge cases
    // =========================================================================

    @isTest
    static void testEmptyEntriesListIsNoOp() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);

        Test.startTest();
        writer.logActions(new List<AuditLogEntry>());
        Test.stopTest();

        System.assertEquals(0, mock.insertedBulk.size(), 'Empty list should produce no DML calls');
    }

    @isTest
    static void testNullEntriesListIsNoOp() {
        MockDmlHandler mock = new MockDmlHandler();
        AuditLogWriter writer = new AuditLogWriter(mock);

        Test.startTest();
        writer.logActions(null);
        Test.stopTest();

        System.assertEquals(0, mock.insertedBulk.size(), 'Null list should produce no DML calls');
    }
}
