/**
 * Unit and integration tests for MetadataIntegrityService, DeploymentManifestParser,
 * ManifestComponent, MetadataCheckResult, and MetadataIntegrityResult.
 *
 * Uses mock HTTP callouts loaded from the MockToolingApiResponses static resource
 * for consistent, fixture-based testing.
 */
@isTest
private class MetadataIntegrityServiceTest {

    // =========================================================================
    // Mock HTTP callout — routes responses based on Tooling API object in URL
    // =========================================================================

    private class ToolingApiMock implements HttpCalloutMock {
        private Map<String, HttpResponse> responsesByObject;
        private HttpResponse defaultResponse;

        ToolingApiMock() {
            responsesByObject = new Map<String, HttpResponse>();
            defaultResponse   = makeOkResponse('{"totalSize":0,"done":true,"records":[]}');
        }

        ToolingApiMock withDefault(Integer code, String body) {
            defaultResponse = makeResponse(code, body);
            return this;
        }

        ToolingApiMock forObject(String toolingObject, String body) {
            responsesByObject.put(toolingObject, makeOkResponse(body));
            return this;
        }

        ToolingApiMock forObjectError(String toolingObject, Integer code, String body) {
            responsesByObject.put(toolingObject, makeResponse(code, body));
            return this;
        }

        public HttpResponse respond(HttpRequest req) {
            String url = req.getEndpoint();
            for (String obj : responsesByObject.keySet()) {
                // The Tooling object appears in the FROM clause of the URL-encoded SOQL
                if (url.contains(EncodingUtil.urlEncode('FROM ' + obj, 'UTF-8'))
                        || url.contains('FROM+' + obj)
                        || url.contains(obj)) {
                    return responsesByObject.get(obj);
                }
            }
            return defaultResponse;
        }

        private static HttpResponse makeOkResponse(String body) {
            return makeResponse(200, body);
        }

        private static HttpResponse makeResponse(Integer code, String body) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            return res;
        }
    }

    // =========================================================================
    // Helpers to load fixtures from the static resource
    // =========================================================================

    private static Map<String, Object> loadFixtures() {
        StaticResource sr = [SELECT Body FROM StaticResource WHERE Name = 'MockToolingApiResponses' LIMIT 1];
        return (Map<String, Object>) JSON.deserializeUntyped(sr.Body.toString());
    }

    private static String fixture(String key) {
        Map<String, Object> fixtures = loadFixtures();
        return JSON.serialize(fixtures.get(key));
    }

    // =========================================================================
    // Test setup helper
    // =========================================================================

    private static SmokeTestExecution__c createExecution(String manifestJson) {
        SmokeTestExecution__c exec = new SmokeTestExecution__c(
            DeploymentManifest__c = manifestJson
        );
        insert exec;
        return exec;
    }

    // =========================================================================
    // DeploymentManifestParser unit tests
    // =========================================================================

    @isTest
    static void testParser_validJson_returnsParsedComponents() {
        String json = '[{"name":"AccountService","type":"ApexClass"},{"name":"Account_Flow","type":"Flow"}]';
        List<ManifestComponent> result = DeploymentManifestParser.parse(json);
        System.assertEquals(2, result.size(), 'Should parse 2 components');
        System.assertEquals('AccountService', result[0].componentName);
        System.assertEquals('ApexClass',      result[0].componentType);
        System.assertEquals('Account_Flow',   result[1].componentName);
        System.assertEquals('Flow',           result[1].componentType);
    }

    @isTest
    static void testParser_nullInput_returnsEmptyList() {
        List<ManifestComponent> result = DeploymentManifestParser.parse(null);
        System.assertEquals(0, result.size(), 'null input should return empty list');
    }

    @isTest
    static void testParser_blankInput_returnsEmptyList() {
        List<ManifestComponent> result = DeploymentManifestParser.parse('   ');
        System.assertEquals(0, result.size(), 'blank input should return empty list');
    }

    @isTest
    static void testParser_emptyArray_returnsEmptyList() {
        List<ManifestComponent> result = DeploymentManifestParser.parse('[]');
        System.assertEquals(0, result.size(), 'empty array should return empty list');
    }

    @isTest
    static void testParser_malformedJson_throwsParseException() {
        try {
            DeploymentManifestParser.parse('{not valid json}]');
            System.assert(false, 'Expected ManifestParseException for malformed JSON');
        } catch (DeploymentManifestParser.ManifestParseException ex) {
            System.assert(ex.getMessage().contains('malformed JSON'), 'Exception should mention malformed JSON');
        }
    }

    @isTest
    static void testParser_rootObject_throwsParseException() {
        try {
            DeploymentManifestParser.parse('{"name":"AccountService","type":"ApexClass"}');
            System.assert(false, 'Expected ManifestParseException for root object');
        } catch (DeploymentManifestParser.ManifestParseException ex) {
            System.assert(ex.getMessage().contains('JSON array'), 'Exception should mention array requirement');
        }
    }

    @isTest
    static void testParser_missingNameField_throwsParseException() {
        try {
            DeploymentManifestParser.parse('[{"type":"ApexClass"}]');
            System.assert(false, 'Expected ManifestParseException for missing name');
        } catch (DeploymentManifestParser.ManifestParseException ex) {
            System.assert(ex.getMessage().contains('"name"'), 'Exception should mention name field');
        }
    }

    @isTest
    static void testParser_missingTypeField_throwsParseException() {
        try {
            DeploymentManifestParser.parse('[{"name":"AccountService"}]');
            System.assert(false, 'Expected ManifestParseException for missing type');
        } catch (DeploymentManifestParser.ManifestParseException ex) {
            System.assert(ex.getMessage().contains('"type"'), 'Exception should mention type field');
        }
    }

    @isTest
    static void testParser_duplicateEntries_areDeduplicated() {
        String json = '[{"name":"AccountService","type":"ApexClass"},{"name":"AccountService","type":"ApexClass"}]';
        List<ManifestComponent> result = DeploymentManifestParser.parse(json);
        System.assertEquals(1, result.size(), 'Duplicates should be deduplicated');
    }

    @isTest
    static void testParser_differentTypes_notDeduplicated() {
        String json = '[{"name":"AccountService","type":"ApexClass"},{"name":"AccountService","type":"ApexTrigger"}]';
        List<ManifestComponent> result = DeploymentManifestParser.parse(json);
        System.assertEquals(2, result.size(), 'Same name different type should not be deduplicated');
    }

    // =========================================================================
    // ManifestComponent value class tests
    // =========================================================================

    @isTest
    static void testManifestComponent_blankName_throwsException() {
        try {
            new ManifestComponent('', 'ApexClass');
            System.assert(false, 'Expected exception for blank name');
        } catch (Exception ex) {
            System.assert(ex.getMessage().contains('componentName'), 'Should mention componentName');
        }
    }

    @isTest
    static void testManifestComponent_blankType_throwsException() {
        try {
            new ManifestComponent('AccountService', '  ');
            System.assert(false, 'Expected exception for blank type');
        } catch (Exception ex) {
            System.assert(ex.getMessage().contains('componentType'), 'Should mention componentType');
        }
    }

    // =========================================================================
    // MetadataIntegrityResult aggregation tests
    // =========================================================================

    @isTest
    static void testResult_addComponentResult_incrementsTotals() {
        MetadataIntegrityResult result = new MetadataIntegrityResult();
        result.addComponentResult(new MetadataCheckResult(
            MetadataCheckResult.Status.PASS, 'Comp1', 'ApexClass', 'Exists', 'Found', 'OK'));
        result.addComponentResult(new MetadataCheckResult(
            MetadataCheckResult.Status.FAIL, 'Comp2', 'ApexClass', 'Exists', 'Not found', 'Missing'));
        result.addComponentResult(new MetadataCheckResult(
            MetadataCheckResult.Status.WARNING, 'Comp3', 'Flow', 'Active', 'Inactive', 'Inactive flow'));

        System.assertEquals(3, result.totalComponents, 'totalComponents should be 3');
        System.assertEquals(1, result.passedCount,    'passedCount should be 1');
        System.assertEquals(1, result.failedCount,    'failedCount should be 1');
        System.assertEquals(1, result.warningCount,   'warningCount should be 1');
        System.assertEquals(3, result.checkResults.size(), 'checkResults should have 3 entries');
    }

    @isTest
    static void testResult_addServiceMessage_doesNotIncrementTotalComponents() {
        MetadataIntegrityResult result = new MetadataIntegrityResult();
        result.addServiceMessage(new MetadataCheckResult(
            MetadataCheckResult.Status.WARNING, 'manifest', 'DeploymentManifest',
            'Non-empty', 'Empty', 'No manifest'));

        System.assertEquals(0, result.totalComponents, 'Service message should not count towards totalComponents');
        System.assertEquals(1, result.warningCount,    'warningCount should be 1');
    }

    // =========================================================================
    // MetadataIntegrityService — all-pass scenario
    // =========================================================================

    @isTest
    static void testVerify_allComponentsFound_allPass() {
        String manifest = '[{"name":"AccountService","type":"ApexClass"},{"name":"ContactService","type":"ApexClass"}]';
        SmokeTestExecution__c exec = createExecution(manifest);

        String apexResponse = fixture('ApexClass_allFound');
        Test.setMock(HttpCalloutMock.class, new ToolingApiMock().forObject('ApexClass', apexResponse));

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(2, result.totalComponents, 'Should have 2 components');
        System.assertEquals(2, result.passedCount,     'Both should pass');
        System.assertEquals(0, result.failedCount,     'No failures expected');
        System.assertEquals(0, result.warningCount,    'No warnings expected');
        System.assertNotEquals(null, result.executionTimestamp, 'Timestamp should be set');
    }

    // =========================================================================
    // MetadataIntegrityService — partial fail (missing component)
    // =========================================================================

    @isTest
    static void testVerify_missingComponent_producesFailResult() {
        String manifest = '[{"name":"AccountService","type":"ApexClass"}]';
        SmokeTestExecution__c exec = createExecution(manifest);

        // Return empty records — component not in org
        String emptyResponse = fixture('ApexClass_empty');
        Test.setMock(HttpCalloutMock.class, new ToolingApiMock().forObject('ApexClass', emptyResponse));

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(1, result.totalComponents, 'Should have 1 component');
        System.assertEquals(0, result.passedCount,     'No passes expected');
        System.assertEquals(1, result.failedCount,     'Should be 1 failure');
        System.assertEquals('Not found', result.checkResults[0].actualState, 'actualState should be Not found');
    }

    // =========================================================================
    // MetadataIntegrityService — FlowDefinition inactive → FAIL
    // =========================================================================

    @isTest
    static void testVerify_flowDefinition_inactiveFlow_producesFail() {
        String manifest = '[{"name":"Inactive_Flow","type":"FlowDefinition"}]';
        SmokeTestExecution__c exec = createExecution(manifest);

        String flowInactive = fixture('FlowDefinition_inactive');
        Test.setMock(HttpCalloutMock.class, new ToolingApiMock().forObject('FlowDefinition', flowInactive));

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(1, result.totalComponents, '1 component');
        System.assertEquals(1, result.failedCount,     'Inactive flow should fail');
        System.assertEquals('Inactive', result.checkResults[0].actualState, 'actualState should be Inactive');
    }

    @isTest
    static void testVerify_flowDefinition_activeFlow_producesPass() {
        String manifest = '[{"name":"Account_Flow","type":"FlowDefinition"}]';
        SmokeTestExecution__c exec = createExecution(manifest);

        String flowActive = fixture('FlowDefinition_active');
        Test.setMock(HttpCalloutMock.class, new ToolingApiMock().forObject('FlowDefinition', flowActive));

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(1, result.passedCount, 'Active flow should pass');
    }

    // =========================================================================
    // MetadataIntegrityService — Tooling API HTTP errors
    // =========================================================================

    @isTest
    static void testVerify_toolingApi500_allComponentsWarning() {
        String manifest = '[{"name":"AccountService","type":"ApexClass"}]';
        SmokeTestExecution__c exec = createExecution(manifest);

        Test.setMock(HttpCalloutMock.class,
            new ToolingApiMock().withDefault(500, fixture('error_500')));

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(1, result.warningCount, 'API error should produce WARNING');
        System.assertEquals(0, result.failedCount,  'Not FAIL for API error');
        System.assert(
            result.checkResults[0].detail.contains('HTTP 500'),
            'Detail should contain HTTP status code'
        );
    }

    @isTest
    static void testVerify_toolingApi401_sessionExpiredWarning() {
        String manifest = '[{"name":"AccountService","type":"ApexClass"}]';
        SmokeTestExecution__c exec = createExecution(manifest);

        Test.setMock(HttpCalloutMock.class,
            new ToolingApiMock().withDefault(401, '{"message":"Session expired"}'));

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(1, result.warningCount, '401 should produce WARNING');
        System.assert(
            result.checkResults[0].detail.contains('401'),
            'Detail should mention 401 status'
        );
    }

    @isTest
    static void testVerify_toolingApi403_permissionWarning() {
        String manifest = '[{"name":"AccountService","type":"ApexClass"}]';
        SmokeTestExecution__c exec = createExecution(manifest);

        Test.setMock(HttpCalloutMock.class,
            new ToolingApiMock().withDefault(403, fixture('error_403')));

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(1, result.warningCount, '403 should produce WARNING');
        System.assert(
            result.checkResults[0].detail.contains('403'),
            'Detail should mention 403 status'
        );
    }

    // =========================================================================
    // MetadataIntegrityService — edge cases
    // =========================================================================

    @isTest
    static void testVerify_emptyManifest_returnsServiceWarning() {
        SmokeTestExecution__c exec = createExecution('[]');

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(0, result.totalComponents, 'No components expected');
        System.assertEquals(1, result.warningCount,    'Should have service-level warning');
        System.assert(
            result.checkResults[0].detail.contains('empty'),
            'Detail should mention empty manifest'
        );
    }

    @isTest
    static void testVerify_nullManifest_returnsServiceWarning() {
        SmokeTestExecution__c exec = createExecution(null);

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(0, result.totalComponents, 'No components expected');
        System.assertEquals(1, result.warningCount,    'Should have service-level warning');
    }

    @isTest
    static void testVerify_malformedManifest_returnsServiceFail() {
        SmokeTestExecution__c exec = createExecution('{bad json}');

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(0, result.totalComponents, 'No components expected');
        System.assertEquals(1, result.failedCount,     'Parse error should be FAIL');
    }

    @isTest
    static void testVerify_unsupportedComponentType_returnsWarning() {
        String manifest = '[{"name":"MyObject","type":"UnknownType"}]';
        SmokeTestExecution__c exec = createExecution(manifest);

        // No callout should happen for unsupported types
        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(1, result.totalComponents, '1 component');
        System.assertEquals(1, result.warningCount,    'Unsupported type should be WARNING');
        System.assert(
            result.checkResults[0].detail.contains('Unsupported'),
            'Detail should mention unsupported'
        );
    }

    // =========================================================================
    // MetadataIntegrityService — multiple component types (batch strategy)
    // =========================================================================

    @isTest
    static void testVerify_multipleTypes_oneCalloutPerType() {
        String manifest = '[{"name":"AccountService","type":"ApexClass"},{"name":"AccountTrigger","type":"ApexTrigger"}]';
        SmokeTestExecution__c exec = createExecution(manifest);

        ToolingApiMock mock = new ToolingApiMock()
            .forObject('ApexClass',   fixture('ApexClass_allFound'))
            .forObject('ApexTrigger', fixture('ApexTrigger_found'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(2, result.totalComponents, '2 components from 2 types');
        System.assertEquals(2, result.passedCount,     'Both should pass');
    }

    @isTest
    static void testVerify_apexClassInactive_producesWarning() {
        String manifest = '[{"name":"LegacyClass","type":"ApexClass"}]';
        SmokeTestExecution__c exec = createExecution(manifest);

        Test.setMock(HttpCalloutMock.class,
            new ToolingApiMock().forObject('ApexClass', fixture('ApexClass_inactive')));

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(1, result.warningCount, 'Inactive Apex class should be WARNING');
        System.assertEquals('Inactive', result.checkResults[0].actualState);
    }

    // =========================================================================
    // MetadataIntegrityService — result persistence (AC-7)
    // =========================================================================

    @isTest
    static void testVerify_persistsResults_toSmokeTestResultRecords() {
        String manifest = '[{"name":"AccountService","type":"ApexClass"}]';
        SmokeTestExecution__c exec = createExecution(manifest);

        Test.setMock(HttpCalloutMock.class,
            new ToolingApiMock().forObject('ApexClass', fixture('ApexClass_allFound')));

        Test.startTest();
        new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        List<SmokeTestResult__c> persisted = [
            SELECT Id, Execution__c, ResultType__c, ScenarioType__c,
                   Status__c, ComponentName__c, ComponentType__c,
                   ExpectedState__c, ActualState__c, ErrorMessage__c
            FROM SmokeTestResult__c
            WHERE Execution__c = :exec.Id
        ];

        System.assertEquals(1, persisted.size(), 'One SmokeTestResult__c should be persisted');
        SmokeTestResult__c r = persisted[0];
        System.assertEquals('METADATA_INTEGRITY', r.ResultType__c,   'ResultType should be METADATA_INTEGRITY');
        System.assertEquals('Metadata',           r.ScenarioType__c, 'ScenarioType should be Metadata');
        System.assertEquals('Pass',               r.Status__c,       'Status should be Pass');
        System.assertEquals('AccountService',     r.ComponentName__c, 'ComponentName should be AccountService');
        System.assertEquals('ApexClass',          r.ComponentType__c, 'ComponentType should be ApexClass');
        System.assertNotEquals(null, r.ExpectedState__c, 'ExpectedState should be set');
        System.assertNotEquals(null, r.ActualState__c,   'ActualState should be set');
    }

    @isTest
    static void testVerify_multipleResults_allPersistedWithCorrectStatus() {
        String manifest = '[{"name":"AccountService","type":"ApexClass"},{"name":"MissingClass","type":"ApexClass"}]';
        SmokeTestExecution__c exec = createExecution(manifest);

        // Only AccountService is in the response; MissingClass is absent
        Test.setMock(HttpCalloutMock.class,
            new ToolingApiMock().forObject('ApexClass', fixture('ApexClass_allFound')));

        Test.startTest();
        new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        List<SmokeTestResult__c> results = [
            SELECT Status__c, ComponentName__c
            FROM SmokeTestResult__c
            WHERE Execution__c = :exec.Id
            ORDER BY ComponentName__c
        ];

        System.assertEquals(2, results.size(), 'Two results should be persisted');
        // AccountService → Pass, MissingClass → Fail
        Map<String, String> statusByName = new Map<String, String>();
        for (SmokeTestResult__c r : results) {
            statusByName.put(r.ComponentName__c, r.Status__c);
        }
        System.assertEquals('Pass', statusByName.get('AccountService'), 'AccountService should Pass');
        System.assertEquals('Fail', statusByName.get('MissingClass'),   'MissingClass should Fail');
    }

    // =========================================================================
    // Integration test: end-to-end with realistic manifest
    // =========================================================================

    @isTest
    static void testIntegration_realisticManifest_endToEnd() {
        String manifest = '[' +
            '{"name":"AccountService","type":"ApexClass"},' +
            '{"name":"statusBanner","type":"LWC"},' +
            '{"name":"Account_Flow","type":"FlowDefinition"},' +
            '{"name":"SmokeTest_Admin","type":"PermissionSet"}' +
        ']';
        SmokeTestExecution__c exec = createExecution(manifest);

        ToolingApiMock mock = new ToolingApiMock()
            .forObject('ApexClass',                fixture('ApexClass_allFound'))
            .forObject('LightningComponentBundle', fixture('LightningComponentBundle_found'))
            .forObject('FlowDefinition',           fixture('FlowDefinition_active'))
            .forObject('PermissionSet',            fixture('PermissionSet_found'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        MetadataIntegrityResult result = new MetadataIntegrityService().verify(exec.Id);
        Test.stopTest();

        System.assertEquals(4, result.totalComponents, '4 components in manifest');
        System.assertEquals(4, result.passedCount,     'All 4 should pass');
        System.assertEquals(0, result.failedCount,     'No failures');
        System.assertEquals(0, result.warningCount,    'No warnings');

        List<SmokeTestResult__c> persisted = [
            SELECT Status__c FROM SmokeTestResult__c
            WHERE Execution__c = :exec.Id
        ];
        System.assertEquals(4, persisted.size(), 'All 4 results should be persisted');
        for (SmokeTestResult__c r : persisted) {
            System.assertEquals('Pass', r.Status__c, 'All persisted results should be Pass');
        }
    }
}
