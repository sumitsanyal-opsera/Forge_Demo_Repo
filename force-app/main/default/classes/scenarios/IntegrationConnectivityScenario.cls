/**
 * Smoke test scenario: External integration endpoint connectivity validation.
 *
 * Performs an HTTP GET to a configurable endpoint URL and verifies that the
 * response status code is in the 200-299 range. Use Named Credentials in
 * production to avoid storing URLs or tokens in Custom Metadata Types.
 *
 * SmokeTestContext parameters (either endpointUrl OR namedCredential required):
 *   endpointUrl      - full URL or Named Credential callout URL (callout:MyNC/path)
 *   namedCredential  - Named Credential API name; expanded to callout:name if endpointUrl absent
 *
 * Timeout: 10 seconds (10 000 ms).
 * isCritical: true — integration failures often indicate org-wide connectivity issues.
 */
public with sharing class IntegrationConnectivityScenario implements ISmokeTestScenario {

    public static final String SCENARIO_NAME = 'Integration_Callout';
    private static final Integer CALLOUT_TIMEOUT_MS = 10000;
    private static final Integer MAX_ERROR_LEN = 1000;

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

            String endpointUrl = buildEndpointUrl(context);
            if (String.isBlank(endpointUrl)) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'CONFIGURATION_ERROR',
                    'Neither endpointUrl nor namedCredential parameter is configured in SmokeTestContext');
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpointUrl);
            req.setMethod('GET');
            req.setTimeout(CALLOUT_TIMEOUT_MS);

            HttpResponse res = new Http().send(req);
            Integer statusCode = res.getStatusCode();

            if (statusCode < 200 || statusCode >= 300) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'ENDPOINT_ERROR',
                    'Endpoint returned HTTP ' + statusCode + ' (expected 2xx). Endpoint: ' + sanitiseUrl(endpointUrl));
            }

            return ScenarioResult.success(SCENARIO_NAME, System.currentTimeMillis() - start);

        } catch (CalloutException ce) {
            return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                'CALLOUT_EXCEPTION', cap(ce.getMessage()));
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
            'Validates external integration endpoint connectivity by performing an HTTP GET and verifying a 200-level response',
            true,
            'Integration',
            100
        );
    }

    public GovernorBudgetConfig getGovernorBudget() {
        return new GovernorBudgetConfig();
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private static String buildEndpointUrl(SmokeTestContext context) {
        String url = getStringParam(context, 'endpointUrl');
        if (!String.isBlank(url)) {
            return url;
        }
        String nc = getStringParam(context, 'namedCredential');
        return String.isBlank(nc) ? null : 'callout:' + nc;
    }

    /** Strips query parameters from URL before including it in error messages. */
    private static String sanitiseUrl(String url) {
        if (String.isBlank(url)) { return ''; }
        Integer qIdx = url.indexOf('?');
        return (qIdx >= 0) ? url.substring(0, qIdx) : url;
    }

    private static String getStringParam(SmokeTestContext context, String key) {
        Object val = context.parameters.get(key);
        return (val instanceof String) ? (String) val : null;
    }

    private static String cap(String s) {
        if (s == null) { return null; }
        return s.length() > MAX_ERROR_LEN ? s.substring(0, MAX_ERROR_LEN) : s;
    }
}
