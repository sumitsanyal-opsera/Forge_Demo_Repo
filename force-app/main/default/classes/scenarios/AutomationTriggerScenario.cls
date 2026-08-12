/**
 * Smoke test scenario: Apex trigger and automation side-effect validation.
 *
 * Creates an Account via SmokeTestDataFactory (which fires any configured
 * before/after-insert triggers, Process Builders, or Flows on Account) and
 * then re-queries the record to verify that a specific field was updated to
 * an expected value by the automation.
 *
 * Required SmokeTestContext parameters:
 *   triggerFieldName          - API name of the Account field to inspect
 *   triggerFieldExpectedValue - value that automation should have written to that field
 *
 * The field name is allow-listed against Account schema before use in dynamic
 * SOQL to prevent injection (OWASP A03).
 */
public with sharing class AutomationTriggerScenario implements ISmokeTestScenario {

    public static final String SCENARIO_NAME = 'Automation_Trigger';
    private static final Integer MAX_ERROR_LEN = 1000;

    // Set in @isTest to exercise exception-handling branches
    @TestVisible static Exception injectException        = null;
    @TestVisible static Boolean   triggerAssertFail       = false;
    // Overrides the actual re-queried field value for unit tests; avoids
    // dependency on org-specific automation being installed in the test org.
    @TestVisible static String    injectTriggerFieldValue = null;

    // =========================================================================
    // ISmokeTestScenario implementation
    // =========================================================================

    public ScenarioResult execute(SmokeTestContext context) {
        Long start = System.currentTimeMillis();
        try {
            if (injectException  != null) { throw injectException; }
            if (triggerAssertFail)        { System.assert(false, 'Test-triggered assertion failure'); }

            String fieldName     = getStringParam(context, 'triggerFieldName');
            String expectedValue = getStringParam(context, 'triggerFieldExpectedValue');

            if (String.isBlank(fieldName)) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'CONFIGURATION_ERROR',
                    'triggerFieldName parameter is required but not configured in SmokeTestContext');
            }
            if (expectedValue == null) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'CONFIGURATION_ERROR',
                    'triggerFieldExpectedValue parameter is required but not configured in SmokeTestContext');
            }

            // Allow-list the field name against Account schema before use in dynamic SOQL
            Map<String, Schema.SObjectField> accountFields =
                Account.SObjectType.getDescribe().fields.getMap();
            if (!accountFields.containsKey(fieldName.toLowerCase())) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'CONFIGURATION_ERROR',
                    'Field \'' + fieldName + '\' does not exist on Account. ' +
                    'Verify the triggerFieldName parameter is a valid Account API field name.');
            }

            // CREATE ACCOUNT — fires any configured automation on insert
            Account acc = SmokeTestDataFactory.createAccount();
            System.assertNotEquals(null, acc.Id,
                'Account Id must be populated after insert');

            // CHECK AUTOMATION SIDE EFFECT
            String actualValue;
            if (injectTriggerFieldValue != null) {
                actualValue = injectTriggerFieldValue;
            } else {
                // Dynamic SOQL is safe here: fieldName is allow-listed against Account schema
                Id accId = acc.Id;
                List<SObject> records = Database.query(
                    'SELECT ' + fieldName +
                    ' FROM Account WHERE Id = :accId WITH SECURITY_ENFORCED LIMIT 1'
                );
                actualValue = records.isEmpty() ? null : String.valueOf(records[0].get(fieldName));
            }

            if (actualValue != expectedValue) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'AUTOMATION_NOT_FIRED',
                    'Automation side effect not detected on Account.' +
                    ' Field \'' + fieldName + '\' expected [' + expectedValue +
                    '] but got [' + actualValue + '].' +
                    ' This may indicate that a trigger or automation was deactivated by the deployment.');
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
            'Validates that Apex triggers and automation fire correctly after deployment by inserting an Account and verifying expected field side effects',
            true,
            'Automation',
            70
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
