/**
 * Smoke test scenario: Salesforce Flow activation and execution validation.
 *
 * Verifies that a target Flow is active (has an ActiveVersionId) and, for
 * AutoLaunchedFlow types, can be invoked without errors. Screen Flows and
 * other types that cannot be called programmatically are validated for
 * activation status only.
 *
 * Flow API name is supplied via SmokeTestContext.parameters['flowApiName'].
 */
public with sharing class FlowExecutionScenario implements ISmokeTestScenario {

    public static final String SCENARIO_NAME = 'Flow_Execution';
    private static final Integer MAX_ERROR_LEN = 1000;

    // Set in @isTest to exercise exception-handling branches without real Flow metadata
    @TestVisible static Exception       injectException      = null;
    @TestVisible static Boolean         triggerAssertFail     = false;
    // FlowDefinitionView rows cannot be inserted in @isTest — inject a mock result
    @TestVisible static FlowCheckResult injectFlowCheckResult = null;
    // Simulates a Flow execution error inside the Flow.Interview invocation block
    @TestVisible static Boolean         simulateFlowExecError = false;

    /** Result wrapper for the FlowDefinitionView query; injectable for unit tests. */
    public class FlowCheckResult {
        public Boolean found       = false;
        public Boolean active      = false;
        public String  processType = null;
        public String  label       = null;
    }

    // =========================================================================
    // ISmokeTestScenario implementation
    // =========================================================================

    public ScenarioResult execute(SmokeTestContext context) {
        Long start = System.currentTimeMillis();
        try {
            if (injectException  != null) { throw injectException; }
            if (triggerAssertFail)        { System.assert(false, 'Test-triggered assertion failure'); }

            String flowApiName = resolveFlowApiName(context);
            if (String.isBlank(flowApiName)) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'CONFIGURATION_ERROR',
                    'flowApiName parameter is required but not configured in SmokeTestContext');
            }

            FlowCheckResult check = (injectFlowCheckResult != null)
                ? injectFlowCheckResult
                : checkFlow(flowApiName);

            if (!check.found) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'FLOW_NOT_FOUND',
                    'No Flow found with API name: ' + flowApiName +
                    '. Verify the flow API name is correct and the flow is deployed.');
            }

            if (!check.active) {
                String label = (check.label != null) ? check.label : flowApiName;
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'FLOW_INACTIVE',
                    'Flow \'' + label + '\' has no active version — it may have been deactivated by the last deployment.');
            }

            // AutoLaunchedFlows can be invoked programmatically; screen flows and other
            // types can only be verified for activation status (cannot be called from Apex).
            if ('AutoLaunchedFlow'.equalsIgnoreCase(check.processType)) {
                try {
                    if (simulateFlowExecError) {
                        throw new IllegalArgumentException('Simulated flow execution error');
                    }
                    Flow.Interview interview = Flow.Interview.createInterview(
                        flowApiName, new Map<String, Object>()
                    );
                    interview.start();
                } catch (Exception flowEx) {
                    return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                        'FLOW_EXECUTION_ERROR', cap(flowEx.getMessage()));
                }
            }

            return ScenarioResult.success(SCENARIO_NAME, System.currentTimeMillis() - start);

        } catch (DmlException e) {
            return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                'DML_EXCEPTION', cap(e.getMessage()));
        } catch (QueryException e) {
            return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                'QUERY_EXCEPTION', cap(e.getMessage()));
        } catch (System.AssertException e) {
            return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                'ASSERTION_FAILED', cap(e.getMessage()));
        } catch (Exception e) {
            return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                'UNEXPECTED_ERROR', cap(e.getMessage()));
        }
    }

    public ScenarioMetadata getMetadata() {
        return new ScenarioMetadata(
            SCENARIO_NAME,
            'Validates that a configured Salesforce Flow is active and, for AutoLaunchedFlows, executes without errors',
            true,
            'Automation',
            60
        );
    }

    public GovernorBudgetConfig getGovernorBudget() {
        return new GovernorBudgetConfig();
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    @TestVisible
    private FlowCheckResult checkFlow(String flowApiName) {
        FlowCheckResult result = new FlowCheckResult();
        List<FlowDefinitionView> flows = [
            SELECT ActiveVersionId, ApiName, Label, ProcessType
            FROM   FlowDefinitionView
            WHERE  ApiName = :flowApiName
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        result.found = !flows.isEmpty();
        if (result.found) {
            result.active      = (flows[0].ActiveVersionId != null);
            result.processType = flows[0].ProcessType;
            result.label       = flows[0].Label;
        }
        return result;
    }

    private static String resolveFlowApiName(SmokeTestContext context) {
        Object val = context.parameters.get('flowApiName');
        return (val instanceof String) ? (String) val : null;
    }

    private static String cap(String s) {
        if (s == null) { return null; }
        return s.length() > MAX_ERROR_LEN ? s.substring(0, MAX_ERROR_LEN) : s;
    }
}
