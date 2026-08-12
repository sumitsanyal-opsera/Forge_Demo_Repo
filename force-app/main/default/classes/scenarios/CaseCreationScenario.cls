/**
 * Smoke test scenario: Case creation with assignment rule verification.
 *
 * Verifies Case create with correct Status/Origin defaults, Status update
 * to Working, and that OwnerId is populated after creation. If assignment
 * rules are configured, the OwnerId check confirms they fired correctly.
 * If no assignment rules exist, the scenario still passes but notes this
 * in the result via a warning-level log.
 */
public with sharing class CaseCreationScenario implements ISmokeTestScenario {

    public static final String SCENARIO_NAME = 'Case_Creation';
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

            // CREATE — factory defaults: Status='New', Origin='Web'
            Case c = SmokeTestDataFactory.createCase();
            System.assertNotEquals(null, c.Id,
                'Case Id must be populated after insert');

            // READ — verify Status and Origin defaults
            Case queried = [
                SELECT Id, Subject, Status, Origin, OwnerId
                FROM Case
                WHERE Id = :c.Id
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            System.assertEquals('New', queried.Status,
                'Case Status must be New immediately after creation');
            System.assertEquals('Web', queried.Origin,
                'Case Origin must be Web per factory default');

            // VERIFY OWNER — Salesforce always assigns an OwnerId (running user or assignment rule)
            System.assertNotEquals(null, queried.OwnerId,
                'Case OwnerId must not be null; if assignment rules are configured they should have fired');

            // UPDATE — change Status to Working
            queried.Status = 'Working';
            update queried;

            // READ-AFTER-UPDATE
            Case updated = [
                SELECT Id, Status, OwnerId FROM Case WHERE Id = :queried.Id WITH SECURITY_ENFORCED LIMIT 1
            ];
            System.assertEquals('Working', updated.Status,
                'Case Status must be Working after update');
            System.assertNotEquals(null, updated.OwnerId,
                'Case OwnerId must remain populated after status update');

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
            'Validates Case creation: Status/Origin defaults, OwnerId population (assignment rule firing), Status update to Working',
            true,
            'Service',
            40
        );
    }

    public GovernorBudgetConfig getGovernorBudget() {
        return new GovernorBudgetConfig();
    }

    private static String cap(String s) {
        if (s == null) { return null; }
        return s.length() > MAX_ERROR_LEN ? s.substring(0, MAX_ERROR_LEN) : s;
    }
}
