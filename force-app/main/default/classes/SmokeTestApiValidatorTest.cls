/**
 * Unit tests for SmokeTestApiValidator.
 *
 * Test fixtures (static final constants): VALID_RUN_REQUEST, INVALID_JSON,
 * MISSING_REQUIRED_FIELD, INVALID_SCENARIO_NAME, OUT_OF_RANGE_THRESHOLD,
 * DISALLOWED_WEBHOOK_URL.
 *
 * Webhook URL tests rely on SmokeTestAlertRoute__mdt.DevOps_PipelineFailures
 * having CallbackUrlPattern__c = 'hooks.slack.com' — this record is part of
 * the package metadata and is accessible in @isTest context without SeeAllData.
 *
 * Coverage target: ≥90% on SmokeTestApiValidator.cls.
 */
@isTest
private class SmokeTestApiValidatorTest {

    // =========================================================================
    // Test fixture constants
    // =========================================================================

    private static final String VALID_RUN_REQUEST =
        '{"targetOrg":"my-sandbox-01",' +
        '"scenarioFilter":["Account_CRUD","Contact_CRUD","Lead-Conversion"],' +
        '"rollbackPolicyOverride":"RECOMMEND_ONLY",' +
        '"timeout":120,' +
        '"securityScoreThreshold":80}';

    private static final String INVALID_JSON =
        '{invalid-json-structure: this is not valid JSON!}';

    private static final String MISSING_REQUIRED_FIELD =
        '{"scenarioFilter":["Account_CRUD"],"timeout":120}';

    private static final String INVALID_SCENARIO_NAME =
        '{"targetOrg":"my-org","scenarioFilter":["Account CRUD with spaces!"]}';

    private static final String OUT_OF_RANGE_THRESHOLD =
        '{"targetOrg":"my-org","securityScoreThreshold":150}';

    private static final String DISALLOWED_WEBHOOK_URL =
        '{"targetOrg":"my-org","webhookCallbackUrl":"https://evil.attacker.com/steal"}';

    // =========================================================================
    // validateRunRequest — valid payloads
    // =========================================================================

    @isTest
    static void testValidRunRequestPassesAllValidation() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(VALID_RUN_REQUEST);

        System.assert(result.isValid, 'Full valid request must pass; errors: ' + result.errors);
        System.assertEquals(0, result.errors.size(), 'No errors expected for a valid request');
        System.assertNotEquals(null, result.parsedRequest, 'Parsed request must be populated');
        System.assertEquals('my-sandbox-01', result.parsedRequest.get('targetOrg'));
    }

    @isTest
    static void testMinimalValidRunRequestTargetOrgOnly() {
        String json = '{"targetOrg":"my-sandbox-01"}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assert(result.isValid, 'Minimal valid request (targetOrg only) must pass');
    }

    @isTest
    static void testValidTargetOrgWithHyphensAndUnderscores() {
        String json = '{"targetOrg":"my_sandbox-01_test"}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assert(result.isValid, 'targetOrg with hyphens and underscores must be valid');
    }

    @isTest
    static void testValidScenarioNamesWithAllAllowedChars() {
        String json = '{"targetOrg":"my-org","scenarioFilter":["Account_CRUD","Lead-Conversion","Opp1"]}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assert(result.isValid, 'Valid scenario names must pass; errors: ' + result.errors);
    }

    @isTest
    static void testValidSecurityScoreThresholdAt80() {
        String json = '{"targetOrg":"my-org","securityScoreThreshold":80}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assert(result.isValid, 'Threshold 80 must be valid');
    }

    @isTest
    static void testValidSecurityScoreThresholdBoundaries() {
        SmokeTestApiValidator.ValidationResult r0 =
            SmokeTestApiValidator.validateRunRequest('{"targetOrg":"org","securityScoreThreshold":0}');
        SmokeTestApiValidator.ValidationResult r100 =
            SmokeTestApiValidator.validateRunRequest('{"targetOrg":"org","securityScoreThreshold":100}');

        System.assert(r0.isValid,   'Threshold 0 must be valid');
        System.assert(r100.isValid, 'Threshold 100 must be valid');
    }

    @isTest
    static void testValidTimeoutBoundaries() {
        SmokeTestApiValidator.ValidationResult r60 =
            SmokeTestApiValidator.validateRunRequest('{"targetOrg":"org","timeout":60}');
        SmokeTestApiValidator.ValidationResult r600 =
            SmokeTestApiValidator.validateRunRequest('{"targetOrg":"org","timeout":600}');

        System.assert(r60.isValid,  'Timeout 60 must be valid');
        System.assert(r600.isValid, 'Timeout 600 must be valid');
    }

    @isTest
    static void testAllValidRollbackPolicies() {
        for (String policy : new List<String>{'RECOMMEND_ONLY', 'AUTO_ROLLBACK', 'MANUAL_APPROVAL'}) {
            String json = '{"targetOrg":"org","rollbackPolicyOverride":"' + policy + '"}';
            SmokeTestApiValidator.ValidationResult result =
                SmokeTestApiValidator.validateRunRequest(json);
            System.assert(result.isValid, policy + ' must be a valid rollback policy');
        }
    }

    // =========================================================================
    // validateRunRequest — null / empty / oversized body
    // =========================================================================

    @isTest
    static void testNullBodyReturnsRequiredError() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(null);

        System.assertFalse(result.isValid, 'Null body must be invalid');
        System.assert(!result.errors.isEmpty(), 'Must have at least one error');
        System.assert(result.errors[0].toLowerCase().contains('required'),
            'Error must say "required"; got: ' + result.errors[0]);
    }

    @isTest
    static void testEmptyStringBodyReturnsRequiredError() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest('');

        System.assertFalse(result.isValid, 'Empty string body must be invalid');
        System.assert(result.errors[0].toLowerCase().contains('required'));
    }

    @isTest
    static void testWhitespaceOnlyBodyReturnsRequiredError() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest('   ');

        System.assertFalse(result.isValid, 'Whitespace-only body must be invalid');
    }

    @isTest
    static void testOversizedBodyReturnsError() {
        // Construct a body just over the 1 MB limit
        String oversized = '{"targetOrg":"' + 'X'.repeat(SmokeTestApiValidator.MAX_BODY_LENGTH) + '"}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(oversized);

        System.assertFalse(result.isValid, 'Body exceeding 1MB must be rejected');
        System.assert(result.errors[0].toLowerCase().contains('size'),
            'Error must mention size; got: ' + result.errors[0]);
    }

    // =========================================================================
    // validateRunRequest — malformed JSON
    // =========================================================================

    @isTest
    static void testInvalidJsonReturnsParseError() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(INVALID_JSON);

        System.assertFalse(result.isValid, 'Invalid JSON must be rejected');
        Boolean foundInvalidJson = false;
        for (String err : result.errors) {
            if (err.contains('INVALID_JSON')) {
                foundInvalidJson = true;
                break;
            }
        }
        System.assert(foundInvalidJson, 'Error must contain INVALID_JSON code; got: ' + result.errors);
    }

    @isTest
    static void testJsonArrayBodyReturnsError() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest('["not","an","object"]');

        System.assertFalse(result.isValid, 'JSON array body must be rejected as not an object');
        System.assert(result.errors[0].contains('INVALID_JSON'),
            'Error must contain INVALID_JSON indicator');
    }

    // =========================================================================
    // validateRunRequest — required field: targetOrg
    // =========================================================================

    @isTest
    static void testMissingTargetOrgReturnsError() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(MISSING_REQUIRED_FIELD);

        System.assertFalse(result.isValid, 'Missing targetOrg must be invalid');
        Boolean foundTargetOrgError = false;
        for (String err : result.errors) {
            if (err.contains('targetOrg')) {
                foundTargetOrgError = true;
                break;
            }
        }
        System.assert(foundTargetOrgError, 'Error must identify "targetOrg"; got: ' + result.errors);
    }

    @isTest
    static void testTargetOrgWithSpacesReturnsError() {
        String json = '{"targetOrg":"my org with spaces"}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assertFalse(result.isValid, 'targetOrg with spaces must be invalid');
        System.assert(result.errors[0].contains('targetOrg'));
    }

    @isTest
    static void testTargetOrgWithSpecialCharsReturnsError() {
        String json = '{"targetOrg":"my@org!"}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assertFalse(result.isValid, 'targetOrg with @ and ! must be invalid');
    }

    // =========================================================================
    // validateRunRequest — unknown fields
    // =========================================================================

    @isTest
    static void testUnknownFieldReturnsError() {
        String json = '{"targetOrg":"my-org","injectionField":"malicious_value"}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assertFalse(result.isValid, 'Unknown field must be rejected');
        Boolean foundUnknownError = false;
        for (String err : result.errors) {
            if (err.contains('injectionField')) {
                foundUnknownError = true;
                break;
            }
        }
        System.assert(foundUnknownError, 'Error must name the unknown field; got: ' + result.errors);
    }

    // =========================================================================
    // validateRunRequest — scenarioFilter
    // =========================================================================

    @isTest
    static void testInvalidScenarioNameWithSpacesReturnsError() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(INVALID_SCENARIO_NAME);

        System.assertFalse(result.isValid, 'Scenario name with spaces must be rejected');
        Boolean foundScenarioError = false;
        for (String err : result.errors) {
            if (err.contains('scenarioFilter')) {
                foundScenarioError = true;
                break;
            }
        }
        System.assert(foundScenarioError, 'Error must identify "scenarioFilter"; got: ' + result.errors);
    }

    @isTest
    static void testScenarioFilterAsStringNotArrayReturnsError() {
        String json = '{"targetOrg":"my-org","scenarioFilter":"Account_CRUD"}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assertFalse(result.isValid, 'scenarioFilter as a string must be rejected');
        System.assert(result.errors[0].contains('scenarioFilter'));
    }

    @isTest
    static void testScenarioNameExceeding80CharsReturnsError() {
        String longName = 'A'.repeat(81); // 81 chars exceeds 80 char limit
        String json = '{"targetOrg":"my-org","scenarioFilter":["' + longName + '"]}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assertFalse(result.isValid, 'Scenario name > 80 chars must be rejected');
    }

    // =========================================================================
    // validateRunRequest — securityScoreThreshold
    // =========================================================================

    @isTest
    static void testSecurityScoreThresholdNegativeReturnsError() {
        String json = '{"targetOrg":"my-org","securityScoreThreshold":-1}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assertFalse(result.isValid, 'Threshold -1 must be invalid');
        System.assert(result.errors[0].contains('securityScoreThreshold'));
    }

    @isTest
    static void testSecurityScoreThresholdAbove100ReturnsError() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(OUT_OF_RANGE_THRESHOLD);

        System.assertFalse(result.isValid, 'Threshold 150 must be invalid');
        Boolean hasThresholdError = false;
        for (String err : result.errors) {
            if (err.contains('securityScoreThreshold')) {
                hasThresholdError = true;
                break;
            }
        }
        System.assert(hasThresholdError, 'Error must identify securityScoreThreshold; got: ' + result.errors);
    }

    // =========================================================================
    // validateRunRequest — timeout
    // =========================================================================

    @isTest
    static void testTimeoutBelowMinimumReturnsError() {
        String json = '{"targetOrg":"my-org","timeout":30}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assertFalse(result.isValid, 'Timeout 30 seconds must be invalid (min 60)');
        System.assert(result.errors[0].contains('timeout'));
    }

    @isTest
    static void testTimeoutAboveMaximumReturnsError() {
        String json = '{"targetOrg":"my-org","timeout":601}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assertFalse(result.isValid, 'Timeout 601 must be invalid (max 600)');
    }

    // =========================================================================
    // validateRunRequest — rollbackPolicyOverride
    // =========================================================================

    @isTest
    static void testInvalidRollbackPolicyReturnsError() {
        String json = '{"targetOrg":"my-org","rollbackPolicyOverride":"UNKNOWN_POLICY"}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assertFalse(result.isValid, 'Invalid rollback policy must be rejected');
        System.assert(result.errors[0].contains('rollbackPolicyOverride'));
    }

    // =========================================================================
    // validateRunRequest — webhookCallbackUrl
    // =========================================================================

    @isTest
    static void testWebhookUrlInAllowListIsAccepted() {
        // hooks.slack.com is in SmokeTestAlertRoute__mdt.DevOps_PipelineFailures.CallbackUrlPattern__c
        String json = '{"targetOrg":"my-org","webhookCallbackUrl":"https://hooks.slack.com/services/T123/B456"}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assert(result.isValid,
            'URL with allowed host hooks.slack.com must pass; errors: ' + result.errors);
    }

    @isTest
    static void testWebhookUrlNotInAllowListReturnsError() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(DISALLOWED_WEBHOOK_URL);

        System.assertFalse(result.isValid, 'URL with disallowed host must be rejected');
        Boolean foundAllowListError = false;
        for (String err : result.errors) {
            if (err.contains('allowed list')) {
                foundAllowListError = true;
                break;
            }
        }
        System.assert(foundAllowListError,
            'Error must say "Callback URL not in allowed list"; got: ' + result.errors);
    }

    @isTest
    static void testWebhookUrlWithHttpSchemeReturnsError() {
        String json = '{"targetOrg":"my-org","webhookCallbackUrl":"http://hooks.slack.com/services/T123"}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assertFalse(result.isValid, 'HTTP webhook URL must be rejected (HTTPS only)');
        Boolean foundHttpsError = false;
        for (String err : result.errors) {
            if (err.toLowerCase().contains('https')) {
                foundHttpsError = true;
                break;
            }
        }
        System.assert(foundHttpsError, 'Error must mention HTTPS requirement; got: ' + result.errors);
    }

    // =========================================================================
    // validateRunRequest — multiple errors collected in one call
    // =========================================================================

    @isTest
    static void testMultipleValidationErrorsAllCollected() {
        // Payload with: unknown field + invalid scenario name + out-of-range threshold
        String json =
            '{"targetOrg":"my-org",' +
            '"badField":"x",' +
            '"scenarioFilter":["invalid name with spaces!"],' +
            '"securityScoreThreshold":200}';
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateRunRequest(json);

        System.assertFalse(result.isValid);
        System.assert(result.errors.size() >= 3,
            'Must collect all errors in single call; got ' + result.errors.size() + ': ' + result.errors);
    }

    // =========================================================================
    // validateExecutionId
    // =========================================================================

    @isTest
    static void testValidExecutionId18Chars() {
        // 18-character alphanumeric Salesforce ID
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateExecutionId('a001B000003Ib00AAC');

        System.assert(result.isValid, '18-char alphanumeric ID must be valid; errors: ' + result.errors);
    }

    @isTest
    static void testNullExecutionIdReturnsRequiredError() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateExecutionId(null);

        System.assertFalse(result.isValid, 'Null execution ID must be invalid');
        System.assert(result.errors[0].toLowerCase().contains('required'));
    }

    @isTest
    static void testBlankExecutionIdReturnsRequiredError() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateExecutionId('   ');

        System.assertFalse(result.isValid, 'Blank execution ID must be invalid');
    }

    @isTest
    static void testShortExecutionIdReturnsFormatError() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateExecutionId('001ABC');

        System.assertFalse(result.isValid, '6-char ID must be invalid');
        System.assert(result.errors[0].contains('18-character'),
            'Error must mention 18-character; got: ' + result.errors[0]);
    }

    @isTest
    static void testExecutionIdWithHyphensReturnsFormatError() {
        // Hyphens are not allowed in Salesforce IDs
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateExecutionId('a001-B000-003I-b00A');

        System.assertFalse(result.isValid, 'ID with hyphens must be invalid');
    }

    @isTest
    static void testExecutionIdWithCorrectLengthButSpecialCharsInvalid() {
        // 18 chars but contains @ which is not alphanumeric
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateExecutionId('001B000003Ib00@AC#');

        System.assertFalse(result.isValid, 'ID with special chars must be invalid');
    }

    // =========================================================================
    // validateHealthRequest
    // =========================================================================

    @isTest
    static void testHealthRequestAlwaysValid() {
        SmokeTestApiValidator.ValidationResult result =
            SmokeTestApiValidator.validateHealthRequest();

        System.assert(result.isValid, 'Health check must always be valid');
        System.assertEquals(0, result.errors.size(), 'Health check must have no errors');
        System.assertNotEquals(null, result.parsedRequest, 'parsedRequest must be initialized');
    }

    // =========================================================================
    // extractHost — private helper via @TestVisible
    // =========================================================================

    @isTest
    static void testExtractHostWithPath() {
        System.assertEquals('hooks.slack.com',
            SmokeTestApiValidator.extractHost('https://hooks.slack.com/services/T123/B456'),
            'extractHost must strip path');
    }

    @isTest
    static void testExtractHostNoPath() {
        System.assertEquals('api.example.com',
            SmokeTestApiValidator.extractHost('https://api.example.com'),
            'extractHost must work without path');
    }

    @isTest
    static void testExtractHostWithPort() {
        System.assertEquals('api.example.com',
            SmokeTestApiValidator.extractHost('https://api.example.com:8443/path'),
            'extractHost must strip port');
    }

    @isTest
    static void testExtractHostWithQueryString() {
        System.assertEquals('api.example.com',
            SmokeTestApiValidator.extractHost('https://api.example.com/path?foo=bar'),
            'extractHost must correctly handle path with query string');
    }
}
