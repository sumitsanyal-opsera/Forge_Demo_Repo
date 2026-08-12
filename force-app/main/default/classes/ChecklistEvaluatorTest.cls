@isTest
private class ChecklistEvaluatorTest {

    // -------------------------------------------------------------------------
    // Mock HTTP callout
    // -------------------------------------------------------------------------

    private class MockHttpCallout implements ChecklistContext.IHttpCallout {
        private Integer statusCode;
        private String  body;
        private Boolean throwCalloutException;

        MockHttpCallout(Integer statusCode, String body) {
            this.statusCode            = statusCode;
            this.body                  = body;
            this.throwCalloutException = false;
        }

        MockHttpCallout asCalloutException() {
            this.throwCalloutException = true;
            return this;
        }

        public HttpResponse send(HttpRequest req) {
            if (throwCalloutException) {
                throw new CalloutException('Network error');
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    // -------------------------------------------------------------------------
    // Mock DML handler
    // -------------------------------------------------------------------------

    private class MockDmlHandler implements IDmlHandler {
        List<SObject> inserted = new List<SObject>();
        public void insertRecord(SObject record) { inserted.add(record); }
        public void insertRecords(List<SObject> records) { inserted.addAll(records); }
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private static ManifestComponent flowComponent(String name) {
        ManifestComponent c = new ManifestComponent();
        c.componentName = name;
        c.componentType = 'Flow';
        return c;
    }

    private static ManifestComponent psComponent(String name) {
        ManifestComponent c = new ManifestComponent();
        c.componentName = name;
        c.componentType = 'PermissionSet';
        return c;
    }

    private static ManifestComponent layoutComponent(String name) {
        ManifestComponent c = new ManifestComponent();
        c.componentName = name;
        c.componentType = 'Layout';
        return c;
    }

    private static String flowApiResponse(String devName, String activeVersionId) {
        String avId = activeVersionId != null
            ? '"' + activeVersionId + '"' : 'null';
        return '{"records":[{"DeveloperName":"' + devName
            + '","ActiveVersionId":' + avId + '}]}';
    }

    private static String profileLayoutApiResponse(String layoutName) {
        return '{"records":[{"Layout":{"Name":"' + layoutName + '"},"ProfileId":"00e000000000001AAA"}]}';
    }

    private static ChecklistContext buildCtx(
        List<ManifestComponent> components,
        Map<String, SmokeTestChecklist__mdt> config,
        ChecklistContext.IHttpCallout callout
    ) {
        return new ChecklistContext(null, components, config, callout);
    }

    private static SmokeTestChecklist__mdt soqlConfig(String devName, String query) {
        SmokeTestChecklist__mdt cfg = new SmokeTestChecklist__mdt();
        cfg.DeveloperName = devName;
        cfg.CheckType__c  = 'SOQLValidation';
        cfg.IsEnabled__c  = true;
        cfg.Query__c      = query;
        cfg.ExpectedResult__c = 'records found';
        return cfg;
    }

    // -------------------------------------------------------------------------
    // FlowActivationCheck tests
    // -------------------------------------------------------------------------

    @isTest
    static void flowCheck_noFlowsInManifest_returnsWarning() {
        FlowActivationCheck check = new FlowActivationCheck();
        ChecklistContext ctx = buildCtx(new List<ManifestComponent>(),
            new Map<String, SmokeTestChecklist__mdt>(), null);

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.WARNING, result.status,
            'Should return WARNING when no flows in manifest');
        System.assertEquals('FLOW_ACTIVATION', result.checkType);
        System.assert(result.detail.contains('skipping activation check'), result.detail);
    }

    @isTest
    static void flowCheck_activeFlow_returnsPass() {
        String mockBody = flowApiResponse('My_Flow', 'a00000000000001AAA');
        MockHttpCallout mock = new MockHttpCallout(200, mockBody);

        FlowActivationCheck check = new FlowActivationCheck();
        ChecklistContext ctx = buildCtx(
            new List<ManifestComponent>{ flowComponent('My_Flow') },
            new Map<String, SmokeTestChecklist__mdt>(), mock
        );

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.PASS, result.status,
            'Should return PASS when flow has active version');
    }

    @isTest
    static void flowCheck_inactiveFlow_returnsFail() {
        String mockBody = flowApiResponse('My_Flow', null);
        MockHttpCallout mock = new MockHttpCallout(200, mockBody);

        FlowActivationCheck check = new FlowActivationCheck();
        ChecklistContext ctx = buildCtx(
            new List<ManifestComponent>{ flowComponent('My_Flow') },
            new Map<String, SmokeTestChecklist__mdt>(), mock
        );

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.FAIL, result.status,
            'Should return FAIL when flow has no active version');
        System.assert(result.actualValue.contains('Inactive'), result.actualValue);
    }

    @isTest
    static void flowCheck_flowNotFound_returnsFail() {
        String mockBody = '{"records":[]}';
        MockHttpCallout mock = new MockHttpCallout(200, mockBody);

        FlowActivationCheck check = new FlowActivationCheck();
        ChecklistContext ctx = buildCtx(
            new List<ManifestComponent>{ flowComponent('Missing_Flow') },
            new Map<String, SmokeTestChecklist__mdt>(), mock
        );

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.FAIL, result.status,
            'Should return FAIL when flow not found in org');
        System.assert(result.actualValue.contains('Not found'), result.actualValue);
    }

    @isTest
    static void flowCheck_httpError_returnsWarning() {
        MockHttpCallout mock = new MockHttpCallout(500, 'Internal Server Error');

        FlowActivationCheck check = new FlowActivationCheck();
        ChecklistContext ctx = buildCtx(
            new List<ManifestComponent>{ flowComponent('My_Flow') },
            new Map<String, SmokeTestChecklist__mdt>(), mock
        );

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.WARNING, result.status,
            'Should return WARNING on HTTP error');
        System.assert(result.actualValue.contains('500'), result.actualValue);
    }

    @isTest
    static void flowCheck_calloutException_returnsWarning() {
        MockHttpCallout mock = new MockHttpCallout(200, '').asCalloutException();

        FlowActivationCheck check = new FlowActivationCheck();
        ChecklistContext ctx = buildCtx(
            new List<ManifestComponent>{ flowComponent('My_Flow') },
            new Map<String, SmokeTestChecklist__mdt>(), mock
        );

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.WARNING, result.status,
            'Should return WARNING on callout exception');
    }

    // -------------------------------------------------------------------------
    // PermissionSetAssignmentCheck tests
    // -------------------------------------------------------------------------

    @isTest
    static void psCheck_noPSInManifest_returnsWarning() {
        PermissionSetAssignmentCheck check = new PermissionSetAssignmentCheck();
        ChecklistContext ctx = buildCtx(new List<ManifestComponent>(),
            new Map<String, SmokeTestChecklist__mdt>(), null);

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.WARNING, result.status,
            'Should return WARNING when no permission sets in manifest');
        System.assertEquals('PERMISSION_SET', result.checkType);
    }

    @isTest
    static void psCheck_nonExistentPS_returnsFail() {
        PermissionSetAssignmentCheck check = new PermissionSetAssignmentCheck();
        ChecklistContext ctx = buildCtx(
            new List<ManifestComponent>{ psComponent('Nonexistent_PS_12345') },
            new Map<String, SmokeTestChecklist__mdt>(), null
        );

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.FAIL, result.status,
            'Should return FAIL when permission set has no assignments');
        System.assert(result.actualValue.contains('Unassigned'), result.actualValue);
    }

    @isTest
    static void psCheck_assignedPS_returnsPass() {
        // Use a standard permission set that exists in every org (SmokeTestAdmin or similar)
        // We create a real PermissionSet and assignment for this test
        PermissionSet ps = new PermissionSet(Name = 'ChecklistTest_PS_WO067',
            Label = 'Checklist Test PS');
        insert ps;

        PermissionSetAssignment psa = new PermissionSetAssignment(
            PermissionSetId = ps.Id,
            AssigneeId = UserInfo.getUserId()
        );
        insert psa;

        PermissionSetAssignmentCheck check = new PermissionSetAssignmentCheck();
        ChecklistContext ctx = buildCtx(
            new List<ManifestComponent>{ psComponent(ps.Name) },
            new Map<String, SmokeTestChecklist__mdt>(), null
        );

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.PASS, result.status,
            'Should return PASS when permission set has at least one assignment');
    }

    // -------------------------------------------------------------------------
    // PageLayoutAssignmentCheck tests
    // -------------------------------------------------------------------------

    @isTest
    static void layoutCheck_noLayoutsInManifest_returnsWarning() {
        PageLayoutAssignmentCheck check = new PageLayoutAssignmentCheck();
        ChecklistContext ctx = buildCtx(new List<ManifestComponent>(),
            new Map<String, SmokeTestChecklist__mdt>(), null);

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.WARNING, result.status,
            'Should return WARNING when no layouts in manifest');
        System.assertEquals('PAGE_LAYOUT', result.checkType);
    }

    @isTest
    static void layoutCheck_assignedLayout_returnsPass() {
        String layoutName = 'Account-Account Layout';
        String mockBody = profileLayoutApiResponse(layoutName);
        MockHttpCallout mock = new MockHttpCallout(200, mockBody);

        PageLayoutAssignmentCheck check = new PageLayoutAssignmentCheck();
        ChecklistContext ctx = buildCtx(
            new List<ManifestComponent>{ layoutComponent(layoutName) },
            new Map<String, SmokeTestChecklist__mdt>(), mock
        );

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.PASS, result.status,
            'Should return PASS when layout is assigned to a profile');
    }

    @isTest
    static void layoutCheck_unassignedLayout_returnsFail() {
        String mockBody = '{"records":[]}';
        MockHttpCallout mock = new MockHttpCallout(200, mockBody);

        PageLayoutAssignmentCheck check = new PageLayoutAssignmentCheck();
        ChecklistContext ctx = buildCtx(
            new List<ManifestComponent>{ layoutComponent('Account-Missing Layout') },
            new Map<String, SmokeTestChecklist__mdt>(), mock
        );

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.FAIL, result.status,
            'Should return FAIL when layout has no profile assignment');
        System.assert(result.actualValue.contains('Unassigned'), result.actualValue);
    }

    @isTest
    static void layoutCheck_multipleAssignments_returnsWarning() {
        String layoutName = 'Account-Account Layout';
        String mockBody = '{"records":['
            + '{"Layout":{"Name":"' + layoutName + '"},"ProfileId":"00e000000000001AAA"},'
            + '{"Layout":{"Name":"' + layoutName + '"},"ProfileId":"00e000000000002AAA"}'
            + ']}';
        MockHttpCallout mock = new MockHttpCallout(200, mockBody);

        PageLayoutAssignmentCheck check = new PageLayoutAssignmentCheck();
        ChecklistContext ctx = buildCtx(
            new List<ManifestComponent>{ layoutComponent(layoutName) },
            new Map<String, SmokeTestChecklist__mdt>(), mock
        );

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.WARNING, result.status,
            'Should return WARNING when layout has multiple profile assignments');
    }

    @isTest
    static void layoutCheck_calloutException_returnsWarning() {
        MockHttpCallout mock = new MockHttpCallout(200, '').asCalloutException();

        PageLayoutAssignmentCheck check = new PageLayoutAssignmentCheck();
        ChecklistContext ctx = buildCtx(
            new List<ManifestComponent>{ layoutComponent('Account-Account Layout') },
            new Map<String, SmokeTestChecklist__mdt>(), mock
        );

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.WARNING, result.status,
            'Should return WARNING on callout exception');
    }

    // -------------------------------------------------------------------------
    // ConfigValueCheck tests
    // -------------------------------------------------------------------------

    @isTest
    static void configCheck_noSOQLValidationConfigs_returnsWarning() {
        ConfigValueCheck check = new ConfigValueCheck();
        ChecklistContext ctx = buildCtx(new List<ManifestComponent>(),
            new Map<String, SmokeTestChecklist__mdt>(), null);

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.WARNING, result.status,
            'Should return WARNING when no SOQLValidation entries');
        System.assertEquals('CONFIG_VALUE', result.checkType);
    }

    @isTest
    static void configCheck_queryReturnsRecords_returnsPass() {
        Map<String, SmokeTestChecklist__mdt> config = new Map<String, SmokeTestChecklist__mdt>{
            'Test_Query' => soqlConfig('Test_Query', 'SELECT Id FROM User LIMIT 1')
        };

        ConfigValueCheck check = new ConfigValueCheck();
        ChecklistContext ctx = buildCtx(new List<ManifestComponent>(), config, null);

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.PASS, result.status,
            'Should return PASS when SOQL returns records');
    }

    @isTest
    static void configCheck_queryReturnsNoRecords_returnsFail() {
        Map<String, SmokeTestChecklist__mdt> config = new Map<String, SmokeTestChecklist__mdt>{
            'Empty_Query' => soqlConfig('Empty_Query',
                'SELECT Id FROM Account WHERE Name = \'NONEXISTENT_CHECKLIST_TEST_12345\'')
        };

        ConfigValueCheck check = new ConfigValueCheck();
        ChecklistContext ctx = buildCtx(new List<ManifestComponent>(), config, null);

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.FAIL, result.status,
            'Should return FAIL when SOQL returns no records');
    }

    @isTest
    static void configCheck_invalidSOQL_returnsWarning() {
        Map<String, SmokeTestChecklist__mdt> config = new Map<String, SmokeTestChecklist__mdt>{
            'Bad_Query' => soqlConfig('Bad_Query', 'SELECT BadFieldXYZ FROM User')
        };

        ConfigValueCheck check = new ConfigValueCheck();
        ChecklistContext ctx = buildCtx(new List<ManifestComponent>(), config, null);

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.WARNING, result.status,
            'Should return WARNING when SOQL query throws an exception');
    }

    @isTest
    static void configCheck_blankQuery_returnsWarning() {
        Map<String, SmokeTestChecklist__mdt> config = new Map<String, SmokeTestChecklist__mdt>{
            'Blank_Query' => soqlConfig('Blank_Query', '')
        };

        ConfigValueCheck check = new ConfigValueCheck();
        ChecklistContext ctx = buildCtx(new List<ManifestComponent>(), config, null);

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.WARNING, result.status,
            'Should return WARNING when query is blank');
    }

    @isTest
    static void configCheck_disabledEntry_ignored() {
        SmokeTestChecklist__mdt disabledCfg = new SmokeTestChecklist__mdt();
        disabledCfg.DeveloperName = 'Disabled';
        disabledCfg.CheckType__c  = 'SOQLValidation';
        disabledCfg.IsEnabled__c  = false;
        disabledCfg.Query__c      = 'SELECT Id FROM User LIMIT 1';

        Map<String, SmokeTestChecklist__mdt> config =
            new Map<String, SmokeTestChecklist__mdt>{ 'Disabled' => disabledCfg };

        ConfigValueCheck check = new ConfigValueCheck();
        ChecklistContext ctx = buildCtx(new List<ManifestComponent>(), config, null);

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.WARNING, result.status,
            'Should return WARNING (no enabled entries) when all are disabled');
    }

    // -------------------------------------------------------------------------
    // ScheduledJobCheck tests
    // -------------------------------------------------------------------------

    @isTest
    static void scheduledJobCheck_noJobsScheduled_returnsFail() {
        ScheduledJobCheck check = new ScheduledJobCheck();
        ChecklistContext ctx = buildCtx(new List<ManifestComponent>(),
            new Map<String, SmokeTestChecklist__mdt>(), null);

        ChecklistResult result = check.execute(ctx);

        // In a bare test org, no scheduled jobs are WAITING — should FAIL
        System.assertNotEquals(null, result.status, 'Should return a non-null status');
        System.assertEquals('SCHEDULED_JOB', result.checkType);
    }

    @isTest
    static void scheduledJobCheck_specificJobExpected_missingReturnsFail() {
        SmokeTestChecklist__mdt cfg = new SmokeTestChecklist__mdt();
        cfg.DeveloperName     = 'Validate_Scheduled_Jobs';
        cfg.MasterLabel       = 'Validate Scheduled Jobs';
        cfg.CheckType__c      = 'SOQLValidation';
        cfg.IsEnabled__c      = true;
        cfg.ExpectedResult__c = 'NonExistentJob_12345';

        Map<String, SmokeTestChecklist__mdt> config =
            new Map<String, SmokeTestChecklist__mdt>{ 'Validate_Scheduled_Jobs' => cfg };

        ScheduledJobCheck check = new ScheduledJobCheck();
        ChecklistContext ctx = buildCtx(new List<ManifestComponent>(), config, null);

        ChecklistResult result = check.execute(ctx);

        System.assertEquals(ChecklistResult.Status.FAIL, result.status,
            'Should return FAIL when expected job is not scheduled');
        System.assert(result.actualValue.contains('Not scheduled'), result.actualValue);
    }

    // -------------------------------------------------------------------------
    // ChecklistEvaluator orchestration tests
    // -------------------------------------------------------------------------

    @isTest
    static void evaluator_emptyManifest_returnsAllWarnings() {
        MockDmlHandler mockDml = new MockDmlHandler();
        ChecklistEvaluator.httpCalloutOverride = new MockHttpCallout(200,
            '{"records":[]}');
        ChecklistEvaluator.checklistConfigOverride = new Map<String, SmokeTestChecklist__mdt>();

        ChecklistEvaluator evaluator = new ChecklistEvaluator(mockDml);

        // Create a minimal execution record for the test
        SmokeTestExecution__c exec = new SmokeTestExecution__c();
        insert exec;

        Test.startTest();
        List<ChecklistResult> results = evaluator.evaluate(exec.Id);
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should return 5 results for 5 checks');

        // Empty manifest → all checks should be WARNING (no components to check)
        for (ChecklistResult r : results) {
            System.assertEquals(ChecklistResult.Status.WARNING, r.status,
                r.checkName + ' should return WARNING for empty manifest');
        }

        // Verify persistence
        System.assertEquals(5, mockDml.inserted.size(), 'Should persist 5 SmokeTestResult__c records');
        System.assertEquals('CHECKLIST', ((SmokeTestResult__c) mockDml.inserted[0]).ResultType__c,
            'ResultType__c should be CHECKLIST');
    }

    @isTest
    static void evaluator_withFlowManifest_flowCheckExecuted() {
        MockDmlHandler mockDml = new MockDmlHandler();
        String mockBody = flowApiResponse('TestFlow', 'a00000000000001AAA');
        ChecklistEvaluator.httpCalloutOverride = new MockHttpCallout(200, mockBody);
        ChecklistEvaluator.checklistConfigOverride = new Map<String, SmokeTestChecklist__mdt>();

        SmokeTestExecution__c exec = new SmokeTestExecution__c(
            DeploymentManifest__c = '[{"componentName":"TestFlow","componentType":"Flow"}]'
        );
        insert exec;

        ChecklistEvaluator evaluator = new ChecklistEvaluator(mockDml);

        Test.startTest();
        List<ChecklistResult> results = evaluator.evaluate(exec.Id);
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should always return 5 results');

        ChecklistResult flowResult = null;
        for (ChecklistResult r : results) {
            if ('FLOW_ACTIVATION'.equals(r.checkType)) {
                flowResult = r;
                break;
            }
        }
        System.assertNotEquals(null, flowResult, 'FlowActivationCheck result should be in list');
        System.assertEquals(ChecklistResult.Status.PASS, flowResult.status,
            'Flow check should PASS when mock returns active version');
    }

    @isTest
    static void evaluator_noExecution_returnsWarnings() {
        MockDmlHandler mockDml = new MockDmlHandler();
        ChecklistEvaluator.httpCalloutOverride = new MockHttpCallout(200, '{"records":[]}');
        ChecklistEvaluator.checklistConfigOverride = new Map<String, SmokeTestChecklist__mdt>();

        ChecklistEvaluator evaluator = new ChecklistEvaluator(mockDml);

        Test.startTest();
        List<ChecklistResult> results = evaluator.evaluate(null);
        Test.stopTest();

        // Should still return 5 results (all WARNING for empty context)
        System.assertEquals(5, results.size(), 'Should return 5 results even with null executionId');
    }

    @isTest
    static void evaluator_persistsResultsWithCorrectFields() {
        MockDmlHandler mockDml = new MockDmlHandler();
        ChecklistEvaluator.httpCalloutOverride = new MockHttpCallout(200, '{"records":[]}');
        ChecklistEvaluator.checklistConfigOverride = new Map<String, SmokeTestChecklist__mdt>();

        SmokeTestExecution__c exec = new SmokeTestExecution__c();
        insert exec;

        ChecklistEvaluator evaluator = new ChecklistEvaluator(mockDml);

        Test.startTest();
        evaluator.evaluate(exec.Id);
        Test.stopTest();

        System.assertEquals(5, mockDml.inserted.size());
        SmokeTestResult__c first = (SmokeTestResult__c) mockDml.inserted[0];
        System.assertEquals('CHECKLIST', first.ResultType__c);
        System.assertNotEquals(null, first.ScenarioName__c);
        System.assertNotEquals(null, first.Status__c);
        System.assertEquals(exec.Id, first.Execution__c);
    }
}
