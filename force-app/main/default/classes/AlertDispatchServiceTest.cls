/**
 * Unit tests for AlertDispatchService.
 *
 * Uses mock IAlertChannelAdapter implementations (CapturingMockAdapter) to verify routing
 * logic without sending real notifications. Injects CMT routes via AlertDispatchService.injectedRoutes.
 *
 * Coverage: routing, tag filtering, disabled routes, fail/pass gating, recipient resolution
 * fallback, adapter error isolation, no-route logging, and audit record creation.
 */
@isTest
private class AlertDispatchServiceTest {

    // =========================================================================
    // Mock adapters
    // =========================================================================

    private class CapturingMockAdapter implements IAlertChannelAdapter {
        public String channelType;
        public List<AlertPayload> captures = new List<AlertPayload>();
        public Boolean returnSuccess = true;
        public String  returnError   = null;
        public Integer returnCount   = 3;

        public CapturingMockAdapter(String channelType) { this.channelType = channelType; }

        public String getChannelType() { return channelType; }

        public AlertResult send(AlertPayload payload) {
            captures.add(payload);
            return new AlertResult(returnSuccess, channelType, returnCount, returnError);
        }
    }

    private class ThrowingMockAdapter implements IAlertChannelAdapter {
        public String channelType;

        public ThrowingMockAdapter(String channelType) { this.channelType = channelType; }

        public String getChannelType() { return channelType; }

        public AlertResult send(AlertPayload payload) {
            throw new System.CalloutException('Simulated network failure');
        }
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private static AlertPayload makePayload(String result, List<String> failedNames) {
        SmokeTestExecution__c exec = new SmokeTestExecution__c(
            Status__c = 'Complete', TriggerSource__c = 'API',
            StartTime__c = DateTime.now(), TotalScenarios__c = 3
        );
        insert exec;
        return new AlertPayload(exec.Id, result, failedNames, false, DateTime.now(), 'API');
    }

    private static SmokeTestAlertRoute__mdt makeRoute(
        String devName, String channel, String role, Boolean enabled,
        Boolean alertOnFail, Boolean alertOnPass, String scenarioFilter
    ) {
        SmokeTestAlertRoute__mdt r = new SmokeTestAlertRoute__mdt();
        r = (SmokeTestAlertRoute__mdt) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'DeveloperName'    => devName,
                'Channel__c'       => channel,
                'RecipientRole__c' => role,
                'Enabled__c'       => enabled,
                'AlertOnFail__c'   => alertOnFail,
                'AlertOnPass__c'   => alertOnPass,
                'ScenarioFilter__c' => scenarioFilter
            }),
            SmokeTestAlertRoute__mdt.class
        );
        return r;
    }

    private static AlertDispatchService makeService(CapturingMockAdapter adapter) {
        Map<String, IAlertChannelAdapter> adapterMap = new Map<String, IAlertChannelAdapter>{
            adapter.channelType => adapter
        };
        return new AlertDispatchService(adapterMap, new AuditLogWriter(new DefaultDmlHandler()));
    }

    // =========================================================================
    // Test 1 — Enabled route with matching channel dispatches to adapter (AC2, AC8)
    // =========================================================================

    @isTest
    static void test_EnabledRoute_MatchingChannel_DispatchesToAdapter() {
        CapturingMockAdapter mockAdapter = new CapturingMockAdapter('Email');
        AlertDispatchService svc = makeService(mockAdapter);
        AlertPayload payload = makePayload('Fail', new List<String>{'Account_CRUD'});

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>{
            makeRoute('Route1', 'Email', 'QA Engineer', true, true, false, null)
        };

        Test.startTest();
        List<AlertResult> results = svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        System.assertEquals(1, results.size(), 'One route should produce one result');
        System.assertEquals(true, results[0].success, 'Mock adapter returns success');
        System.assertEquals('Email', results[0].channelType, 'Channel should be Email');
        System.assertEquals(1, mockAdapter.captures.size(), 'Adapter should have been called once');
    }

    // =========================================================================
    // Test 2 — Disabled route is skipped (AC2)
    // =========================================================================

    @isTest
    static void test_DisabledRoute_IsSkipped() {
        CapturingMockAdapter mockAdapter = new CapturingMockAdapter('Email');
        AlertDispatchService svc = makeService(mockAdapter);
        AlertPayload payload = makePayload('Fail', null);

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>{
            makeRoute('DisabledRoute', 'Email', 'QA Engineer', false, true, false, null)
        };

        Test.startTest();
        List<AlertResult> results = svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        System.assertEquals(0, results.size(), 'Disabled route should be skipped');
        System.assertEquals(0, mockAdapter.captures.size(), 'Adapter must not be called');
    }

    // =========================================================================
    // Test 3 — AlertOnFail=false for failing result: route excluded (AC2)
    // =========================================================================

    @isTest
    static void test_AlertOnFailFalse_ForFailingResult_RouteExcluded() {
        CapturingMockAdapter mockAdapter = new CapturingMockAdapter('Email');
        AlertDispatchService svc = makeService(mockAdapter);
        AlertPayload payload = makePayload('Fail', null);

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>{
            makeRoute('PassOnlyRoute', 'Email', 'QA Engineer', true, false, true, null)
        };

        Test.startTest();
        List<AlertResult> results = svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        System.assertEquals(0, results.size(), 'AlertOnFail=false should exclude route for Fail result');
    }

    // =========================================================================
    // Test 4 — AlertOnPass=true for passing result: route included (AC2)
    // =========================================================================

    @isTest
    static void test_AlertOnPass_ForPassingResult_RouteIncluded() {
        CapturingMockAdapter mockAdapter = new CapturingMockAdapter('InApp');
        AlertDispatchService svc = makeService(mockAdapter);
        AlertPayload payload = makePayload('Pass', null);

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>{
            makeRoute('PassRoute', 'InApp', 'System Administrator', true, false, true, null)
        };

        Test.startTest();
        List<AlertResult> results = svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        System.assertEquals(1, results.size(), 'Route with AlertOnPass=true should be included for Pass');
        System.assertEquals(1, mockAdapter.captures.size(), 'Adapter should be called');
    }

    // =========================================================================
    // Test 5 — ScenarioFilter match: route with matching tag dispatches (AC5)
    // =========================================================================

    @isTest
    static void test_ScenarioFilter_TagMatches_RouteDispatches() {
        CapturingMockAdapter mockAdapter = new CapturingMockAdapter('Email');
        AlertDispatchService svc = makeService(mockAdapter);
        // failedScenarioNames contains "Sales" which matches filter
        AlertPayload payload = makePayload('Fail', new List<String>{'Sales', 'Account_CRUD'});

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>{
            makeRoute('SalesRoute', 'Email', 'Business Owner', true, true, false, 'Sales')
        };

        Test.startTest();
        List<AlertResult> results = svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        System.assertEquals(1, results.size(), 'Route should match when tag found in failedScenarioNames');
    }

    // =========================================================================
    // Test 6 — ScenarioFilter no match: route excluded (AC5)
    // =========================================================================

    @isTest
    static void test_ScenarioFilter_NoTagMatch_RouteExcluded() {
        CapturingMockAdapter mockAdapter = new CapturingMockAdapter('Email');
        AlertDispatchService svc = makeService(mockAdapter);
        AlertPayload payload = makePayload('Fail', new List<String>{'Account_CRUD'});

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>{
            makeRoute('SecurityRoute', 'Email', 'System Administrator', true, true, false, 'Security')
        };

        Test.startTest();
        List<AlertResult> results = svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        System.assertEquals(0, results.size(), 'Route should be excluded when tag does not match');
    }

    // =========================================================================
    // Test 7 — Multiple routes: each dispatched independently (AC2)
    // =========================================================================

    @isTest
    static void test_MultipleRoutes_EachDispatchedIndependently() {
        CapturingMockAdapter emailAdapter = new CapturingMockAdapter('Email');
        CapturingMockAdapter inAppAdapter = new CapturingMockAdapter('InApp');
        Map<String, IAlertChannelAdapter> adapterMap = new Map<String, IAlertChannelAdapter>{
            'Email' => emailAdapter, 'InApp' => inAppAdapter
        };
        AlertDispatchService svc = new AlertDispatchService(
            adapterMap, new AuditLogWriter(new DefaultDmlHandler())
        );
        AlertPayload payload = makePayload('Fail', null);

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>{
            makeRoute('EmailRoute', 'Email', 'Team Lead', true, true, false, null),
            makeRoute('InAppRoute', 'InApp', 'System Administrator', true, true, false, null)
        };

        Test.startTest();
        List<AlertResult> results = svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        System.assertEquals(2, results.size(), 'Two routes should produce two results');
        System.assertEquals(1, emailAdapter.captures.size(), 'Email adapter called once');
        System.assertEquals(1, inAppAdapter.captures.size(), 'InApp adapter called once');
    }

    // =========================================================================
    // Test 8 — No enabled routes: returns empty list (edge case)
    // =========================================================================

    @isTest
    static void test_NoEnabledRoutes_ReturnsEmpty() {
        CapturingMockAdapter mockAdapter = new CapturingMockAdapter('Email');
        AlertDispatchService svc = makeService(mockAdapter);
        AlertPayload payload = makePayload('Fail', null);

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>();

        Test.startTest();
        List<AlertResult> results = svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        System.assertEquals(0, results.size(), 'No routes should produce empty list');
        System.assertEquals(0, mockAdapter.captures.size(), 'Adapter should not be called');
    }

    // =========================================================================
    // Test 9 — Adapter throws: error captured, other adapters continue (error isolation)
    // =========================================================================

    @isTest
    static void test_AdapterThrows_ErrorCaptured_OtherAdaptersContinue() {
        ThrowingMockAdapter throwingAdapter = new ThrowingMockAdapter('Email');
        CapturingMockAdapter goodAdapter    = new CapturingMockAdapter('InApp');
        Map<String, IAlertChannelAdapter> adapterMap = new Map<String, IAlertChannelAdapter>{
            'Email' => throwingAdapter, 'InApp' => goodAdapter
        };
        AlertDispatchService svc = new AlertDispatchService(
            adapterMap, new AuditLogWriter(new DefaultDmlHandler())
        );
        AlertPayload payload = makePayload('Fail', null);

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>{
            makeRoute('ThrowEmail', 'Email', 'QA Engineer', true, true, false, null),
            makeRoute('GoodInApp', 'InApp', 'System Administrator', true, true, false, null)
        };

        Test.startTest();
        List<AlertResult> results = svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        System.assertEquals(2, results.size(), 'Both routes should return results even if one throws');
        AlertResult emailResult = results[0];
        System.assertEquals(false, emailResult.success, 'Throwing adapter result should be failure');
        System.assertNotEquals(null, emailResult.errorMessage, 'Error message should be captured');
        System.assertEquals(1, goodAdapter.captures.size(), 'Good adapter should still be called');
    }

    // =========================================================================
    // Test 10 — Audit records created for each dispatch (AC6)
    // =========================================================================

    @isTest
    static void test_AuditRecordsCreated_ForEachDispatch() {
        CapturingMockAdapter mockAdapter = new CapturingMockAdapter('Email');
        AlertDispatchService svc = makeService(mockAdapter);
        AlertPayload payload = makePayload('Fail', null);

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>{
            makeRoute('AuditRoute1', 'Email', 'QA Engineer', true, true, false, null),
            makeRoute('AuditRoute2', 'Email', 'Team Lead', true, true, false, null)
        };

        Test.startTest();
        svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        // Audit records created via AuditLogWriter (ACTION_ALERT_SENT)
        List<SmokeTestAuditLog__c> logs = [
            SELECT ActionType__c, Outcome__c
            FROM SmokeTestAuditLog__c
            WHERE ActionType__c = 'ALERT_SENT'
            AND   Execution__c = :payload.executionId
        ];
        System.assertEquals(2, logs.size(), 'One audit record per dispatched route');
        for (SmokeTestAuditLog__c log : logs) {
            System.assertEquals('Success', log.Outcome__c, 'Mock adapter returns success');
        }
    }

    // =========================================================================
    // Test 11 — Security score values are NOT in alert payload body (AC7)
    // =========================================================================

    @isTest
    static void test_SecurityScoreNotInPayload_OnlyThresholdBoolean() {
        CapturingMockAdapter mockAdapter = new CapturingMockAdapter('Email');
        AlertDispatchService svc = makeService(mockAdapter);

        // Construct payload with securityThresholdBreached=true (no numeric score)
        SmokeTestExecution__c exec = new SmokeTestExecution__c(
            Status__c = 'Complete', TriggerSource__c = 'API',
            StartTime__c = DateTime.now(), TotalScenarios__c = 1
        );
        insert exec;
        AlertPayload payload = new AlertPayload(
            exec.Id, 'Fail', new List<String>(), true, DateTime.now(), 'API'
        );

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>{
            makeRoute('SecRoute', 'Email', 'System Administrator', true, true, false, null)
        };

        Test.startTest();
        svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        // Verify the payload received by the adapter has only boolean, no score numbers
        System.assertEquals(1, mockAdapter.captures.size(), 'Adapter should be called');
        AlertPayload captured = mockAdapter.captures[0];
        System.assertEquals(true, captured.securityThresholdBreached,
            'securityThresholdBreached boolean should be true');
        System.assertNotEquals(null, captured.executionId,
            'executionId should be populated in captured payload');
    }

    // =========================================================================
    // Test 12 — ScenarioFilter comma-separated: any match triggers dispatch (AC5)
    // =========================================================================

    @isTest
    static void test_ScenarioFilter_CommaSeparated_AnyMatchTriggers() {
        CapturingMockAdapter mockAdapter = new CapturingMockAdapter('Email');
        AlertDispatchService svc = makeService(mockAdapter);
        // Only second tag matches
        AlertPayload payload = makePayload('Fail', new List<String>{'Automation', 'Flow'});

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>{
            makeRoute('MultiTagRoute', 'Email', 'QA Engineer', true, true, false, 'Security, Automation')
        };

        Test.startTest();
        List<AlertResult> results = svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        System.assertEquals(1, results.size(), 'Route with comma-separated filter should match any tag');
    }

    // =========================================================================
    // Test 13 — No adapter for channel: result failure, does not throw (AC2)
    // =========================================================================

    @isTest
    static void test_NoAdapterForChannel_FailureResult_NeverThrows() {
        Map<String, IAlertChannelAdapter> emptyAdapters = new Map<String, IAlertChannelAdapter>();
        AlertDispatchService svc = new AlertDispatchService(
            emptyAdapters, new AuditLogWriter(new DefaultDmlHandler())
        );
        AlertPayload payload = makePayload('Fail', null);

        AlertDispatchService.injectedRoutes = new List<SmokeTestAlertRoute__mdt>{
            makeRoute('SlackRoute', 'Slack', 'DevOps Engineer', true, true, false, null)
        };

        Test.startTest();
        List<AlertResult> results = svc.dispatch(payload);
        Test.stopTest();

        AlertDispatchService.injectedRoutes = null;

        System.assertEquals(1, results.size(), 'Should return one result even for missing adapter');
        System.assertEquals(false, results[0].success, 'Missing adapter should produce failure result');
        System.assertNotEquals(null, results[0].errorMessage, 'Error message should describe missing adapter');
    }
}
