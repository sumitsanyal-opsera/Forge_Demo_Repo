@isTest
private class CustomChecklistProcessorTest {

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private static SmokeTestChecklist__mdt makeItem(
        String devName,
        String checkName,
        String checkType,
        Boolean isEnabled,
        String query,
        String expectedResult
    ) {
        SmokeTestChecklist__mdt item = new SmokeTestChecklist__mdt();
        item.DeveloperName    = devName;
        item.CheckName__c     = checkName;
        item.CheckType__c     = checkType;
        item.IsEnabled__c     = isEnabled;
        item.Query__c         = query;
        item.ExpectedResult__c = expectedResult;
        return item;
    }

    private static Map<String, SmokeTestChecklist__mdt> emptyConfig() {
        return new Map<String, SmokeTestChecklist__mdt>();
    }

    // -------------------------------------------------------------------------
    // Disabled items are skipped
    // -------------------------------------------------------------------------

    @isTest
    static void process_disabledItem_isSkipped() {
        SmokeTestChecklist__mdt disabledItem = makeItem(
            'Disabled_Query', 'Disabled Query', 'query', false,
            'SELECT Id FROM User LIMIT 1', '1'
        );
        CustomChecklistProcessor.injectedConfig =
            new List<SmokeTestChecklist__mdt>{ disabledItem };

        CustomChecklistProcessor processor = new CustomChecklistProcessor();
        List<ChecklistResult> results = processor.process(emptyConfig());

        System.assertEquals(0, results.size(),
            'Disabled item should be skipped and produce no result');

        CustomChecklistProcessor.injectedConfig = null;
    }

    // -------------------------------------------------------------------------
    // Non-'query' check type is skipped
    // -------------------------------------------------------------------------

    @isTest
    static void process_configTypeItem_isSkipped() {
        SmokeTestChecklist__mdt configItem = makeItem(
            'Config_Check', 'Config Check', 'config', true,
            'SELECT Id FROM User LIMIT 1', '1'
        );
        CustomChecklistProcessor.injectedConfig =
            new List<SmokeTestChecklist__mdt>{ configItem };

        CustomChecklistProcessor processor = new CustomChecklistProcessor();
        List<ChecklistResult> results = processor.process(emptyConfig());

        System.assertEquals(0, results.size(),
            'Non-query CheckType should be skipped');

        CustomChecklistProcessor.injectedConfig = null;
    }

    @isTest
    static void process_soqlValidationType_isSkipped() {
        SmokeTestChecklist__mdt soqlItem = makeItem(
            'SOQL_Check', 'SOQL Check', 'SOQLValidation', true,
            'SELECT Id FROM User LIMIT 1', '1'
        );
        CustomChecklistProcessor.injectedConfig =
            new List<SmokeTestChecklist__mdt>{ soqlItem };

        CustomChecklistProcessor processor = new CustomChecklistProcessor();
        List<ChecklistResult> results = processor.process(emptyConfig());

        System.assertEquals(0, results.size(),
            'SOQLValidation type should not be processed by CustomChecklistProcessor');

        CustomChecklistProcessor.injectedConfig = null;
    }

    // -------------------------------------------------------------------------
    // Blank/null query → WARNING
    // -------------------------------------------------------------------------

    @isTest
    static void process_blankQuery_returnsWarning() {
        SmokeTestChecklist__mdt item = makeItem(
            'Blank_Query', 'Blank Query Check', 'query', true, '', '1'
        );
        CustomChecklistProcessor.injectedConfig =
            new List<SmokeTestChecklist__mdt>{ item };

        CustomChecklistProcessor processor = new CustomChecklistProcessor();
        List<ChecklistResult> results = processor.process(emptyConfig());

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(ChecklistResult.Status.WARNING, results[0].status,
            'Blank query should produce WARNING status');
        System.assert(results[0].detail.containsIgnoreCase('empty') ||
            results[0].detail.containsIgnoreCase('null'),
            'Detail should describe the empty/null condition: ' + results[0].detail);

        CustomChecklistProcessor.injectedConfig = null;
    }

    // -------------------------------------------------------------------------
    // Invalid query (fails validation) → WARNING
    // -------------------------------------------------------------------------

    @isTest
    static void process_invalidQuery_noLimit_returnsWarning() {
        SmokeTestChecklist__mdt item = makeItem(
            'No_Limit_Query', 'No Limit Check', 'query', true,
            'SELECT Id FROM User', '1'
        );
        CustomChecklistProcessor.injectedConfig =
            new List<SmokeTestChecklist__mdt>{ item };

        CustomChecklistProcessor processor = new CustomChecklistProcessor();
        List<ChecklistResult> results = processor.process(emptyConfig());

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(ChecklistResult.Status.WARNING, results[0].status,
            'Query failing validation should produce WARNING');
        System.assert(results[0].detail.containsIgnoreCase('validation'),
            'Detail should mention validation: ' + results[0].detail);

        CustomChecklistProcessor.injectedConfig = null;
    }

    // -------------------------------------------------------------------------
    // Valid query returning rows — matching expected value → PASS
    // -------------------------------------------------------------------------

    @isTest
    static void process_queryWithMatchingRowCount_returnsPass() {
        // SELECT Id FROM User WHERE IsActive = true LIMIT 1 returns the running user
        // Expected = '1' (one active user row)
        SmokeTestChecklist__mdt item = makeItem(
            'Active_Users', 'Active Users', 'query', true,
            'SELECT Id FROM User WHERE IsActive = true LIMIT 1', '1'
        );
        CustomChecklistProcessor.injectedConfig =
            new List<SmokeTestChecklist__mdt>{ item };

        CustomChecklistProcessor processor = new CustomChecklistProcessor();

        Test.startTest();
        List<ChecklistResult> results = processor.process(emptyConfig());
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(ChecklistResult.Status.PASS, results[0].status,
            'Query matching expected row count should PASS. Detail: ' + results[0].detail);
        System.assertEquals('1', results[0].actualValue,
            'Actual value should be the row count string');

        CustomChecklistProcessor.injectedConfig = null;
    }

    // -------------------------------------------------------------------------
    // Valid query returning rows — mismatched expected value → FAIL
    // -------------------------------------------------------------------------

    @isTest
    static void process_queryWithMismatchedValue_returnsFail() {
        // Expected = '99' but only 1 active user row will be returned
        SmokeTestChecklist__mdt item = makeItem(
            'Mismatch_Check', 'Mismatch Check', 'query', true,
            'SELECT Id FROM User WHERE IsActive = true LIMIT 1', '99'
        );
        CustomChecklistProcessor.injectedConfig =
            new List<SmokeTestChecklist__mdt>{ item };

        CustomChecklistProcessor processor = new CustomChecklistProcessor();

        Test.startTest();
        List<ChecklistResult> results = processor.process(emptyConfig());
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(ChecklistResult.Status.FAIL, results[0].status,
            'Mismatched row count should return FAIL. Detail: ' + results[0].detail);
        System.assertEquals('99', results[0].expectedValue,
            'ExpectedValue should be preserved');

        CustomChecklistProcessor.injectedConfig = null;
    }

    // -------------------------------------------------------------------------
    // Valid query returning rows — blank expected value → PASS (any rows ok)
    // -------------------------------------------------------------------------

    @isTest
    static void process_queryWithBlankExpected_anyRowsPass() {
        SmokeTestChecklist__mdt item = makeItem(
            'Any_Users', 'Any Users', 'query', true,
            'SELECT Id FROM User WHERE IsActive = true LIMIT 5', ''
        );
        CustomChecklistProcessor.injectedConfig =
            new List<SmokeTestChecklist__mdt>{ item };

        CustomChecklistProcessor processor = new CustomChecklistProcessor();

        Test.startTest();
        List<ChecklistResult> results = processor.process(emptyConfig());
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(ChecklistResult.Status.PASS, results[0].status,
            'Blank expected value should PASS when any rows returned');

        CustomChecklistProcessor.injectedConfig = null;
    }

    // -------------------------------------------------------------------------
    // Valid query returning zero rows → FAIL with 'no results'
    // -------------------------------------------------------------------------

    @isTest
    static void process_queryWithZeroRows_returnsFail() {
        SmokeTestChecklist__mdt item = makeItem(
            'Zero_Rows', 'Zero Rows Check', 'query', true,
            'SELECT Id FROM Account WHERE Name = \'NONEXISTENT_ZZ_12345\' LIMIT 1', '1'
        );
        CustomChecklistProcessor.injectedConfig =
            new List<SmokeTestChecklist__mdt>{ item };

        CustomChecklistProcessor processor = new CustomChecklistProcessor();

        Test.startTest();
        List<ChecklistResult> results = processor.process(emptyConfig());
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(ChecklistResult.Status.FAIL, results[0].status,
            'Zero-row query should return FAIL');
        System.assertEquals('0', results[0].actualValue,
            'Actual value should be 0 for empty result set');
        System.assert(results[0].detail.containsIgnoreCase('no results'),
            'Detail should describe empty result: ' + results[0].detail);

        CustomChecklistProcessor.injectedConfig = null;
    }

    // -------------------------------------------------------------------------
    // CheckName__c falls back to DeveloperName when null
    // -------------------------------------------------------------------------

    @isTest
    static void process_nullCheckName_fallsBackToDeveloperName() {
        SmokeTestChecklist__mdt item = new SmokeTestChecklist__mdt();
        item.DeveloperName    = 'Dev_Name_Fallback';
        item.CheckName__c     = null;
        item.CheckType__c     = 'query';
        item.IsEnabled__c     = true;
        item.Query__c         = 'SELECT Id FROM User WHERE IsActive = true LIMIT 1';
        item.ExpectedResult__c = '';

        CustomChecklistProcessor.injectedConfig =
            new List<SmokeTestChecklist__mdt>{ item };

        CustomChecklistProcessor processor = new CustomChecklistProcessor();

        Test.startTest();
        List<ChecklistResult> results = processor.process(emptyConfig());
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals('Dev_Name_Fallback', results[0].checkName,
            'CheckName should fall back to DeveloperName when CheckName__c is null');

        CustomChecklistProcessor.injectedConfig = null;
    }

    // -------------------------------------------------------------------------
    // Integration: CustomChecklistProcessor called from ChecklistEvaluator
    // -------------------------------------------------------------------------

    @isTest
    static void evaluator_customQueryItem_isIncludedInResults() {
        SmokeTestChecklist__mdt queryItem = makeItem(
            'Evaluator_Test', 'Evaluator Custom Check', 'query', true,
            'SELECT Id FROM User WHERE IsActive = true LIMIT 1', ''
        );

        // Use injectedConfig on the processor so evaluator picks it up via config override
        Map<String, SmokeTestChecklist__mdt> config =
            new Map<String, SmokeTestChecklist__mdt>{ 'Evaluator_Test' => queryItem };
        ChecklistEvaluator.checklistConfigOverride = config;
        ChecklistEvaluator.httpCalloutOverride = new MockHttpCallout(200, '{"records":[]}');

        SmokeTestExecution__c exec = new SmokeTestExecution__c();
        insert exec;

        MockDmlHandler mockDml = new MockDmlHandler();
        ChecklistEvaluator evaluator = new ChecklistEvaluator(mockDml);

        Test.startTest();
        List<ChecklistResult> results = evaluator.evaluate(exec.Id);
        Test.stopTest();

        // 5 default checks + 1 custom query check = 6 total
        System.assertEquals(6, results.size(),
            'Evaluator should return 5 default + 1 custom result. Actual: ' + results.size());

        Boolean foundCustom = false;
        for (ChecklistResult r : results) {
            if ('query'.equals(r.checkType)) {
                foundCustom = true;
                break;
            }
        }
        System.assert(foundCustom, 'Custom query result should be in evaluator output');

        ChecklistEvaluator.checklistConfigOverride = null;
    }

    // -------------------------------------------------------------------------
    // Mock classes
    // -------------------------------------------------------------------------

    private class MockDmlHandler implements IDmlHandler {
        List<SObject> inserted = new List<SObject>();
        public void insertRecord(SObject record)  { inserted.add(record); }
        public void insertRecords(List<SObject> records) { inserted.addAll(records); }
    }

    private class MockHttpCallout implements ChecklistContext.IHttpCallout {
        private Integer statusCode;
        private String  body;
        MockHttpCallout(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
        public HttpResponse send(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }
}
