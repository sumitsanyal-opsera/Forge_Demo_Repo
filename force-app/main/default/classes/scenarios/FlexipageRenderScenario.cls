/**
 * Smoke test scenario: Lightning Flexipage metadata integrity validation.
 *
 * Verifies that a target FlexiPage (Lightning App Builder page) exists and is
 * properly configured by querying the Tooling API. Apex cannot render Lightning
 * pages directly, so this scenario performs a metadata existence check.
 *
 * Tooling API query: SELECT Id, DeveloperName, MasterLabel FROM FlexiPage
 *   WHERE DeveloperName = '<pageDevName>'
 *
 * Required SmokeTestContext parameter:
 *   flexipageDevName - DeveloperName of the FlexiPage to verify
 *
 * Error types:
 *   CONFIGURATION_ERROR  - flexipageDevName missing or contains unsafe characters
 *   TOOLING_API_ERROR    - HTTP callout failed or returned non-2xx status
 *   FLEXIPAGE_NOT_FOUND  - Tooling API query returned totalSize = 0
 *   FLEXIPAGE_MISCONFIGURED - Tooling API returned totalSize > 0 but records array is empty
 *   PARSE_ERROR          - Tooling API response body is not valid JSON
 *   ASSERTION_FAILED     - Internal assertion failure
 *   UNEXPECTED_ERROR     - Uncategorised exception
 */
public with sharing class FlexipageRenderScenario implements ISmokeTestScenario {

    public static final String SCENARIO_NAME = 'PageLayout_Render';
    private static final String API_VERSION   = 'v60.0';
    private static final Integer MAX_ERROR_LEN = 1000;
    private static final Integer CALLOUT_TIMEOUT_MS = 10000;

    @TestVisible static Exception injectException  = null;
    @TestVisible static Boolean   triggerAssertFail = false;

    // =========================================================================
    // ISmokeTestScenario implementation
    // =========================================================================

    public ScenarioResult execute(SmokeTestContext context) {
        Long start = System.currentTimeMillis();
        try {
            if (injectException  != null) { throw injectException; }
            if (triggerAssertFail)        { System.assert(false, 'Test-triggered assertion failure'); }

            String pageDevName = getStringParam(context, 'flexipageDevName');
            if (String.isBlank(pageDevName)) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'CONFIGURATION_ERROR',
                    'flexipageDevName parameter is required but not configured in SmokeTestContext');
            }

            // Validate DeveloperName is a safe API name before embedding in SOQL string
            if (!pageDevName.matches('[a-zA-Z][a-zA-Z0-9_]*')) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'CONFIGURATION_ERROR',
                    'flexipageDevName \'' + pageDevName + '\' is not a valid API name ' +
                    '(must start with a letter and contain only letters, digits, underscores)');
            }

            URL orgUrl = URL.getOrgDomainUrl();
            if (orgUrl == null) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'CONFIGURATION_ERROR',
                    'Org domain URL is not available. Ensure the org has My Domain configured.');
            }

            String soqlQuery = 'SELECT Id, DeveloperName, MasterLabel FROM FlexiPage'
                             + ' WHERE DeveloperName = \'' + pageDevName + '\'';
            String endpoint  = orgUrl.toExternalForm()
                             + '/services/data/' + API_VERSION
                             + '/tooling/query/?q='
                             + EncodingUtil.urlEncode(soqlQuery, 'UTF-8');

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(CALLOUT_TIMEOUT_MS);

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'TOOLING_API_ERROR',
                    'Tooling API returned HTTP ' + res.getStatusCode() +
                    ' for FlexiPage query on \'' + pageDevName + '\'');
            }

            // Parse JSON response: { "totalSize": N, "records": [...] }
            Map<String, Object> bodyMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Object totalSizeObj = bodyMap.get('totalSize');
            Integer totalSize = totalSizeObj != null
                ? Integer.valueOf(String.valueOf(totalSizeObj))
                : 0;

            if (totalSize == 0) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'FLEXIPAGE_NOT_FOUND',
                    'No FlexiPage found with DeveloperName \'' + pageDevName + '\'.' +
                    ' Verify the page was deployed and the DeveloperName is correct.');
            }

            List<Object> records = (List<Object>) bodyMap.get('records');
            if (records == null || records.isEmpty()) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'FLEXIPAGE_MISCONFIGURED',
                    'Tooling API reported totalSize=' + totalSize +
                    ' but returned no records for FlexiPage \'' + pageDevName + '\'.' +
                    ' The page definition may be incomplete or corrupt.');
            }

            return ScenarioResult.success(SCENARIO_NAME, System.currentTimeMillis() - start);

        } catch (CalloutException ce) {
            return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                'TOOLING_API_ERROR', cap(ce.getMessage()));
        } catch (JSONException je) {
            return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                'PARSE_ERROR',
                'Failed to parse Tooling API response: ' + cap(je.getMessage()));
        } catch (System.AssertException ae) {
            return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                'ASSERTION_FAILED', cap(ae.getMessage()));
        } catch (Exception e) {
            return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                'UNEXPECTED_ERROR', cap(e.getMessage()));
        }
    }

    public ScenarioMetadata getMetadata() {
        return new ScenarioMetadata(
            SCENARIO_NAME,
            'Validates Lightning Flexipage metadata integrity by querying the Tooling API to confirm the target page exists and is properly configured',
            false,
            'Platform',
            90
        );
    }

    public GovernorBudgetConfig getGovernorBudget() {
        return new GovernorBudgetConfig();
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private static String getStringParam(SmokeTestContext context, String key) {
        Object val = context.parameters.get(key);
        return (val instanceof String) ? (String) val : null;
    }

    private static String cap(String s) {
        if (s == null) { return null; }
        return s.length() > MAX_ERROR_LEN ? s.substring(0, MAX_ERROR_LEN) : s;
    }
}
