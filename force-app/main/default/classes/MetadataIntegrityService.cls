/**
 * Verifies post-deployment metadata integrity by comparing the deployment
 * manifest stored on SmokeTestExecution__c against the target org's actual
 * metadata state via the Salesforce Tooling API.
 *
 * Algorithm:
 *  1. Load SmokeTestExecution__c.DeploymentManifest__c
 *  2. Parse manifest into List<ManifestComponent>
 *  3. Group components by type
 *  4. One Tooling API callout per distinct component type (batch strategy)
 *  5. Evaluate each component against the API response
 *  6. Persist MetadataCheckResult records as SmokeTestResult__c
 *  7. Return MetadataIntegrityResult aggregate
 *
 * Runs without sharing so the system service can access all execution records
 * regardless of the calling user's record visibility. WITH SECURITY_ENFORCED on
 * SOQL respects field-level security per OWASP A01.
 */
public without sharing class MetadataIntegrityService {

    private static final String API_VERSION = 'v60.0';

    // Manifest componentType → Tooling API SObject name
    @TestVisible
    private static final Map<String, String> TOOLING_OBJECT_MAP = new Map<String, String>{
        'ApexClass'                => 'ApexClass',
        'ApexTrigger'              => 'ApexTrigger',
        'LWC'                      => 'LightningComponentBundle',
        'LightningComponentBundle' => 'LightningComponentBundle',
        'Flow'                     => 'FlowDefinition',
        'FlowDefinition'           => 'FlowDefinition',
        'CustomObject'             => 'EntityDefinition',
        'CustomField'              => 'CustomField',
        'PermissionSet'            => 'PermissionSet',
        'Layout'                   => 'Layout'
    };

    // Tooling API SObject → identifier field (used in WHERE clause and name matching)
    private static final Map<String, String> NAME_FIELD_MAP = new Map<String, String>{
        'ApexClass'                => 'Name',
        'ApexTrigger'              => 'Name',
        'LightningComponentBundle' => 'DeveloperName',
        'FlowDefinition'           => 'DeveloperName',
        'EntityDefinition'         => 'QualifiedApiName',
        'CustomField'              => 'DeveloperName',
        'PermissionSet'            => 'Name',
        'Layout'                   => 'Name'
    };

    // Tooling API SObject → additional field to SELECT for state verification
    private static final Map<String, String> STATE_FIELD_MAP = new Map<String, String>{
        'ApexClass'      => 'Status',
        'ApexTrigger'    => 'Status',
        'FlowDefinition' => 'ActiveVersionId'
    };

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Verifies all components in the deployment manifest for the given execution.
     * Persists one SmokeTestResult__c per component and returns the aggregate result.
     */
    public MetadataIntegrityResult verify(Id executionId) {
        MetadataIntegrityResult result = new MetadataIntegrityResult();

        // Step 1 — Load execution record
        List<SmokeTestExecution__c> execs = [
            SELECT Id, DeploymentManifest__c
            FROM SmokeTestExecution__c
            WHERE Id = :executionId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (execs.isEmpty()) {
            result.addServiceMessage(new MetadataCheckResult(
                MetadataCheckResult.Status.WARNING,
                String.valueOf(executionId), 'Execution',
                'Exists', 'Not found',
                'SmokeTestExecution__c record not found for Id: ' + executionId
            ));
            return result;
        }

        SmokeTestExecution__c execution = execs[0];

        // Step 2 — Parse manifest
        List<ManifestComponent> components;
        try {
            components = DeploymentManifestParser.parse(execution.DeploymentManifest__c);
        } catch (DeploymentManifestParser.ManifestParseException ex) {
            result.addServiceMessage(new MetadataCheckResult(
                MetadataCheckResult.Status.FAIL,
                'manifest', 'DeploymentManifest',
                'Valid JSON array', 'Parse error',
                ErrorSanitizer.sanitize(ex.getMessage())
            ));
            persistResults(executionId, result);
            return result;
        }

        if (components.isEmpty()) {
            result.addServiceMessage(new MetadataCheckResult(
                MetadataCheckResult.Status.WARNING,
                'manifest', 'DeploymentManifest',
                'Non-empty manifest', 'Empty',
                'No deployment manifest provided or manifest is empty'
            ));
            persistResults(executionId, result);
            return result;
        }

        // Step 3 — Group by type
        Map<String, List<ManifestComponent>> byType = groupByType(components);

        // Step 4 + 5 + 6 — One callout per type, then evaluate each component
        for (String compType : byType.keySet()) {
            List<ManifestComponent> typeGroup = byType.get(compType);
            String toolingObject = TOOLING_OBJECT_MAP.get(compType);

            if (toolingObject == null) {
                for (ManifestComponent comp : typeGroup) {
                    result.addComponentResult(new MetadataCheckResult(
                        MetadataCheckResult.Status.WARNING,
                        comp.componentName, comp.componentType,
                        'Supported type', 'Unsupported',
                        'Unsupported component type for automated verification'
                    ));
                }
                continue;
            }

            Map<String, Object> apiResponse;
            try {
                apiResponse = callToolingApi(toolingObject, extractNames(typeGroup));
            } catch (Exception ex) {
                String detail = ErrorSanitizer.sanitize(ex.getMessage());
                for (ManifestComponent comp : typeGroup) {
                    result.addComponentResult(new MetadataCheckResult(
                        MetadataCheckResult.Status.WARNING,
                        comp.componentName, comp.componentType,
                        'API queryable', 'Query failed', detail
                    ));
                }
                continue;
            }

            for (ManifestComponent comp : typeGroup) {
                result.addComponentResult(evaluateComponent(comp, toolingObject, apiResponse));
            }
        }

        // Step 7 — Persist
        persistResults(executionId, result);
        return result;
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private static Map<String, List<ManifestComponent>> groupByType(List<ManifestComponent> components) {
        Map<String, List<ManifestComponent>> grouped = new Map<String, List<ManifestComponent>>();
        for (ManifestComponent comp : components) {
            if (!grouped.containsKey(comp.componentType)) {
                grouped.put(comp.componentType, new List<ManifestComponent>());
            }
            grouped.get(comp.componentType).add(comp);
        }
        return grouped;
    }

    private static Set<String> extractNames(List<ManifestComponent> components) {
        Set<String> names = new Set<String>();
        for (ManifestComponent comp : components) {
            names.add(comp.componentName);
        }
        return names;
    }

    /**
     * Executes one Tooling API REST query for the given SObject type and set of names.
     * Uses the running user's session; in production this should be the integration user.
     *
     * Throws MetadataIntegrityException on non-200 HTTP responses.
     */
    @TestVisible
    private static Map<String, Object> callToolingApi(String toolingObject, Set<String> names) {
        String nameField  = NAME_FIELD_MAP.containsKey(toolingObject)
            ? NAME_FIELD_MAP.get(toolingObject) : 'Name';
        String stateField = STATE_FIELD_MAP.containsKey(toolingObject)
            ? ',' + STATE_FIELD_MAP.get(toolingObject) : '';

        List<String> quotedNames = new List<String>();
        for (String n : names) {
            quotedNames.add('\'' + String.escapeSingleQuotes(n) + '\'');
        }

        String soql = 'SELECT Id,' + nameField + stateField
            + ' FROM ' + toolingObject
            + ' WHERE ' + nameField + ' IN (' + String.join(quotedNames, ',') + ')';

        String endpoint = URL.getSalesforceBaseUrl().toExternalForm()
            + '/services/data/' + API_VERSION + '/tooling/query/?q='
            + EncodingUtil.urlEncode(soql, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');

        HttpResponse res = new Http().send(req);

        Integer statusCode = res.getStatusCode();
        if (statusCode == 401) {
            throw new MetadataIntegrityException(
                'Integration user session expired (HTTP 401)'
            );
        }
        if (statusCode == 403) {
            throw new MetadataIntegrityException(
                'Insufficient permissions (HTTP 403): View Setup and Configuration required'
            );
        }
        if (statusCode != 200) {
            throw new MetadataIntegrityException(
                'Tooling API error HTTP ' + statusCode + ': '
                + ErrorSanitizer.sanitize(res.getBody())
            );
        }

        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static MetadataCheckResult evaluateComponent(
        ManifestComponent comp,
        String toolingObject,
        Map<String, Object> apiResponse
    ) {
        String nameField = NAME_FIELD_MAP.containsKey(toolingObject)
            ? NAME_FIELD_MAP.get(toolingObject) : 'Name';

        List<Object> records = (List<Object>) apiResponse.get('records');
        if (records == null) {
            return new MetadataCheckResult(
                MetadataCheckResult.Status.WARNING,
                comp.componentName, comp.componentType,
                'Exists', 'Invalid API response',
                'Tooling API response missing records array'
            );
        }

        // Find the matching record (case-insensitive name comparison)
        Map<String, Object> matched = null;
        for (Object rec : records) {
            Map<String, Object> record = (Map<String, Object>) rec;
            Object recName = record.get(nameField);
            if (recName != null
                    && comp.componentName.equalsIgnoreCase(String.valueOf(recName))) {
                matched = record;
                break;
            }
        }

        if (matched == null) {
            return new MetadataCheckResult(
                MetadataCheckResult.Status.FAIL,
                comp.componentName, comp.componentType,
                'Exists in org', 'Not found',
                'Component not found in target org via Tooling API'
            );
        }

        // FlowDefinition: verify ActiveVersionId is not null (flow is active)
        if ('FlowDefinition'.equals(toolingObject)) {
            if (matched.get('ActiveVersionId') == null) {
                return new MetadataCheckResult(
                    MetadataCheckResult.Status.FAIL,
                    comp.componentName, comp.componentType,
                    'Active (ActiveVersionId not null)', 'Inactive',
                    'Flow exists but has no active version (ActiveVersionId is null)'
                );
            }
        }

        // ApexClass / ApexTrigger: warn if Status is not Active
        if ('ApexClass'.equals(toolingObject) || 'ApexTrigger'.equals(toolingObject)) {
            Object statusVal = matched.get('Status');
            if (statusVal != null && !'Active'.equals(String.valueOf(statusVal))) {
                return new MetadataCheckResult(
                    MetadataCheckResult.Status.WARNING,
                    comp.componentName, comp.componentType,
                    'Active', String.valueOf(statusVal),
                    comp.componentType + ' exists but Status is not Active: '
                        + String.valueOf(statusVal)
                );
            }
        }

        return new MetadataCheckResult(
            MetadataCheckResult.Status.PASS,
            comp.componentName, comp.componentType,
            'Exists in org', 'Found and verified',
            'Component verified successfully via Tooling API'
        );
    }

    private static void persistResults(Id executionId, MetadataIntegrityResult integrityResult) {
        List<SmokeTestResult__c> records = new List<SmokeTestResult__c>();
        for (MetadataCheckResult check : integrityResult.checkResults) {
            records.add(new SmokeTestResult__c(
                Execution__c     = executionId,
                ResultType__c    = 'METADATA_INTEGRITY',
                ScenarioName__c  = check.componentName,
                ScenarioType__c  = 'Metadata',
                Status__c        = toPicklistLabel(check.status),
                ComponentName__c = check.componentName,
                ComponentType__c = check.componentType,
                ExpectedState__c = check.expectedState,
                ActualState__c   = check.actualState,
                ErrorMessage__c  = check.detail
            ));
        }
        if (!records.isEmpty()) {
            insert records;
        }
    }

    private static String toPicklistLabel(MetadataCheckResult.Status s) {
        if (s == MetadataCheckResult.Status.PASS)    { return 'Pass';    }
        if (s == MetadataCheckResult.Status.FAIL)    { return 'Fail';    }
        if (s == MetadataCheckResult.Status.WARNING) { return 'Warning'; }
        return 'Error';
    }

    public class MetadataIntegrityException extends Exception {}
}
