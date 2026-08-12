/**
 * Centralized input validation service for all SmokeTest REST API endpoints.
 *
 * All methods are stateless static methods — no instance variables, safe for concurrent calls.
 * Methods accept raw inputs and return a ValidationResult; callers map errors to HTTP responses
 * via SmokeTestApiResponse. No dynamic SOQL; webhook allow-list uses a static query with no
 * string interpolation per OWASP A05. Error messages never expose stack traces, class names,
 * or Salesforce org identifiers per OWASP A10.
 *
 * POST /v1/run validation rules:
 *   Required: targetOrg (String, 1-255 chars, [a-zA-Z0-9_-])
 *   Optional: scenarioFilter       (Array of String, each 1-80 chars, [a-zA-Z0-9_-])
 *             webhookCallbackUrl   (String, HTTPS only, host must be in SmokeTestAlertRoute__mdt)
 *             rollbackPolicyOverride (String, one of RECOMMEND_ONLY|AUTO_ROLLBACK|MANUAL_APPROVAL)
 *             timeout              (Integer, 60-600 seconds)
 *             securityScoreThreshold (Integer, 0-100)
 *   Unknown fields: rejected with descriptive error identifying the field name
 */
public with sharing class SmokeTestApiValidator {

    // =========================================================================
    // Constants
    // =========================================================================

    @TestVisible static final Integer MAX_BODY_LENGTH = 1048576; // 1 MB

    private static final Set<String> ALLOWED_RUN_REQUEST_FIELDS = new Set<String>{
        'targetOrg', 'scenarioFilter', 'webhookCallbackUrl',
        'rollbackPolicyOverride', 'timeout', 'securityScoreThreshold'
    };

    private static final Set<String> ALLOWED_ROLLBACK_POLICIES = new Set<String>{
        'RECOMMEND_ONLY', 'AUTO_ROLLBACK', 'MANUAL_APPROVAL'
    };

    // Patterns compiled once at class load — Pattern.compile() is expensive
    private static final Pattern TARGET_ORG_PATTERN    = Pattern.compile('^[a-zA-Z0-9_-]{1,255}$');
    private static final Pattern SCENARIO_NAME_PATTERN = Pattern.compile('^[a-zA-Z0-9_-]{1,80}$');
    private static final Pattern EXECUTION_ID_PATTERN  = Pattern.compile('^[a-zA-Z0-9]{18}$');

    // =========================================================================
    // ValidationResult value class
    // =========================================================================

    /**
     * Returned by all validation methods. Callers check isValid; if false,
     * errors contains human-readable descriptions of every validation failure.
     */
    public class ValidationResult {
        public Boolean          isValid;
        public Map<String,Object> parsedRequest;
        public List<String>     errors;

        public ValidationResult() {
            this.isValid       = true;
            this.parsedRequest = new Map<String,Object>();
            this.errors        = new List<String>();
        }

        public void addError(String message) {
            this.errors.add(message);
            this.isValid = false;
        }
    }

    // =========================================================================
    // Public validation API
    // =========================================================================

    /**
     * Validates the raw JSON body for POST /v1/run.
     * Errors are collected rather than short-circuiting so callers receive
     * all validation failures in a single response.
     */
    public static ValidationResult validateRunRequest(String jsonBody) {
        ValidationResult result = new ValidationResult();

        if (String.isBlank(jsonBody)) {
            result.addError('Request body is required');
            return result;
        }

        if (jsonBody.length() > MAX_BODY_LENGTH) {
            result.addError('Request body exceeds maximum allowed size of 1MB');
            return result;
        }

        Map<String,Object> parsed;
        try {
            Object raw = JSON.deserializeUntyped(jsonBody);
            if (!(raw instanceof Map<String,Object>)) {
                result.addError('INVALID_JSON: Request body must be a JSON object, not an array or scalar');
                return result;
            }
            parsed = (Map<String,Object>) raw;
        } catch (Exception e) {
            result.addError('INVALID_JSON: The request body is not valid JSON');
            return result;
        }

        result.parsedRequest = parsed;

        // Allow-list: reject unknown fields
        for (String fieldName : parsed.keySet()) {
            if (!ALLOWED_RUN_REQUEST_FIELDS.contains(fieldName)) {
                result.addError('Unknown field "' + fieldName + '" is not permitted in run requests');
            }
        }

        // Required field: targetOrg
        validateTargetOrg(parsed.get('targetOrg'), result);

        // Optional fields — only validated if present in payload
        if (parsed.containsKey('scenarioFilter')) {
            validateScenarioFilter(parsed.get('scenarioFilter'), result);
        }
        if (parsed.containsKey('rollbackPolicyOverride')) {
            validateRollbackPolicy(parsed.get('rollbackPolicyOverride'), result);
        }
        if (parsed.containsKey('timeout')) {
            validateTimeout(parsed.get('timeout'), result);
        }
        if (parsed.containsKey('securityScoreThreshold')) {
            validateSecurityScoreThreshold(parsed.get('securityScoreThreshold'), result);
        }
        if (parsed.containsKey('webhookCallbackUrl')) {
            validateWebhookCallbackUrl(parsed.get('webhookCallbackUrl'), result);
        }

        return result;
    }

    /**
     * Validates a Salesforce execution ID path parameter.
     * Accepts standard 18-character alphanumeric Salesforce record IDs.
     */
    public static ValidationResult validateExecutionId(String id) {
        ValidationResult result = new ValidationResult();

        if (String.isBlank(id)) {
            result.addError('Execution ID is required');
            return result;
        }

        if (!EXECUTION_ID_PATTERN.matcher(id).matches()) {
            result.addError(
                'Execution ID must be an 18-character alphanumeric Salesforce record ID');
        }

        return result;
    }

    /**
     * Validates a GET /v1/health request — no body required, always returns valid.
     * Included for interface consistency across all endpoint validators.
     */
    public static ValidationResult validateHealthRequest() {
        return new ValidationResult();
    }

    // =========================================================================
    // Private field validators
    // =========================================================================

    private static void validateTargetOrg(Object value, ValidationResult result) {
        if (value == null) {
            result.addError('Required field "targetOrg" is missing');
            return;
        }
        String targetOrg = String.valueOf(value);
        if (!TARGET_ORG_PATTERN.matcher(targetOrg).matches()) {
            result.addError(
                '"targetOrg" must be 1-255 characters containing only ' +
                'alphanumeric characters, hyphens, or underscores');
        }
    }

    private static void validateScenarioFilter(Object value, ValidationResult result) {
        if (value == null) {
            return; // null optional field is allowed
        }
        if (!(value instanceof List<Object>)) {
            result.addError('"scenarioFilter" must be an array of strings');
            return;
        }
        List<Object> items = (List<Object>) value;
        for (Object item : items) {
            if (item == null) {
                result.addError('"scenarioFilter" must not contain null entries');
                continue;
            }
            String name = String.valueOf(item);
            if (!SCENARIO_NAME_PATTERN.matcher(name).matches()) {
                result.addError(
                    '"scenarioFilter" contains invalid scenario name "' + name +
                    '": names must be 1-80 characters matching pattern [a-zA-Z0-9_-]');
            }
        }
    }

    private static void validateRollbackPolicy(Object value, ValidationResult result) {
        if (value == null) {
            return;
        }
        String policy = String.valueOf(value);
        if (!ALLOWED_ROLLBACK_POLICIES.contains(policy)) {
            result.addError(
                '"rollbackPolicyOverride" must be one of: RECOMMEND_ONLY, AUTO_ROLLBACK, MANUAL_APPROVAL');
        }
    }

    private static void validateTimeout(Object value, ValidationResult result) {
        if (value == null) {
            return;
        }
        Integer t;
        try {
            t = Integer.valueOf(String.valueOf(value));
        } catch (Exception e) {
            result.addError('"timeout" must be an integer value');
            return;
        }
        if (t < 60 || t > 600) {
            result.addError('"timeout" must be between 60 and 600 seconds; received: ' + t);
        }
    }

    private static void validateSecurityScoreThreshold(Object value, ValidationResult result) {
        if (value == null) {
            return;
        }
        Integer threshold;
        try {
            threshold = Integer.valueOf(String.valueOf(value));
        } catch (Exception e) {
            result.addError('"securityScoreThreshold" must be an integer value');
            return;
        }
        if (threshold < 0 || threshold > 100) {
            result.addError(
                '"securityScoreThreshold" must be between 0 and 100; received: ' + threshold);
        }
    }

    private static void validateWebhookCallbackUrl(Object value, ValidationResult result) {
        if (value == null) {
            return;
        }
        String callbackUrl = String.valueOf(value);

        // HTTPS-only — reject HTTP, ftp, file, internal Salesforce URLs (OWASP A01 SSRF)
        if (!callbackUrl.toLowerCase().startsWith('https://')) {
            result.addError('"webhookCallbackUrl" must use the HTTPS scheme');
            return;
        }

        String host = extractHost(callbackUrl);
        if (String.isBlank(host)) {
            result.addError('"webhookCallbackUrl" must specify a valid host');
            return;
        }

        // Query allowed hostname patterns from Custom Metadata Type (static SOQL, no interpolation)
        Set<String> allowedHosts = new Set<String>();
        for (SmokeTestAlertRoute__mdt route : [
            SELECT CallbackUrlPattern__c
            FROM SmokeTestAlertRoute__mdt
            WHERE CallbackUrlPattern__c != null
        ]) {
            allowedHosts.add(route.CallbackUrlPattern__c.toLowerCase());
        }

        if (!allowedHosts.contains(host.toLowerCase())) {
            result.addError('Callback URL not in allowed list');
        }
    }

    /**
     * Extracts the hostname from an HTTPS URL using string parsing.
     * Handles optional path, query, fragment, and port components.
     * Assumes the scheme has already been verified as 'https://'.
     */
    @TestVisible
    private static String extractHost(String url) {
        String withoutScheme = url.removeStart('https://');
        // Strip path and everything after
        Integer pathIdx = withoutScheme.indexOf('/');
        String hostPort = (pathIdx == -1) ? withoutScheme : withoutScheme.substring(0, pathIdx);
        // Strip port number if present (e.g., example.com:8443)
        Integer portIdx = hostPort.indexOf(':');
        return (portIdx == -1) ? hostPort : hostPort.substring(0, portIdx);
    }
}
