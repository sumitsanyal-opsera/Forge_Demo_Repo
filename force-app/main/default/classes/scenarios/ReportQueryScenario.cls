/**
 * Smoke test scenario: Report-style SOQL query execution validation.
 *
 * Executes a configurable SOQL query sourced from SmokeTestContext parameters
 * (which are populated from SmokeTestScenario__mdt at runtime). The query is
 * treated as trusted CMT-sourced input — not user-supplied input — so it is
 * safe to execute via Database.query().
 *
 * Required SmokeTestContext parameter:
 *   soqlQuery - the SOQL statement to execute (e.g. SELECT COUNT(Id) cnt FROM Account)
 *
 * Zero-row results are treated as success; the scenario validates query execution
 * correctness, not data existence. Include WITH SECURITY_ENFORCED in the query
 * string when stored in CMT to enforce field-level security.
 */
public with sharing class ReportQueryScenario implements ISmokeTestScenario {

    public static final String SCENARIO_NAME = 'Report_Generation';
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

            String soqlQuery = getStringParam(context, 'soqlQuery');
            if (String.isBlank(soqlQuery)) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'CONFIGURATION_ERROR',
                    'soqlQuery parameter is required but not configured in SmokeTestContext');
            }

            // Execute the CMT-sourced SOQL query — dynamic SOQL is acceptable because
            // the query originates from a trusted Custom Metadata Type, not user input.
            List<SObject> results = Database.query(soqlQuery);

            return ScenarioResult.success(SCENARIO_NAME, System.currentTimeMillis() - start);

        } catch (System.LimitException le) {
            return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                'GOVERNOR_LIMIT_EXCEEDED', cap(le.getMessage()));
        } catch (QueryException qe) {
            return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                'QUERY_ERROR', cap(qe.getMessage()));
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
            'Validates that a configurable SOQL report query executes without errors — confirms the reporting data model is intact after deployment',
            false,
            'Reporting',
            80
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
