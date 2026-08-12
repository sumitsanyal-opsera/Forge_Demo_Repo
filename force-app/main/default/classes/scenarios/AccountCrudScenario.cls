/**
 * Smoke test scenario: Account CRUD validation.
 *
 * Verifies that create, read-after-write, update, and delete operations
 * work correctly on Account records after a deployment.
 *
 * isCritical=true — Account is the foundational business object; CRUD failure
 * indicates a critical org configuration problem.
 */
public with sharing class AccountCrudScenario implements ISmokeTestScenario {

    public static final String SCENARIO_NAME = 'Account_CRUD';
    private static final Integer MAX_ERROR_LEN = 1000;

    // Set in @isTest to exercise exception-handling branches without real DML failures
    @TestVisible static Exception  injectException   = null;
    @TestVisible static Boolean    triggerAssertFail  = false;

    // =========================================================================
    // ISmokeTestScenario implementation
    // =========================================================================

    public ScenarioResult execute(SmokeTestContext context) {
        Long start = System.currentTimeMillis();
        try {
            if (injectException  != null) { throw injectException; }
            if (triggerAssertFail)        { System.assert(false, 'Test-triggered assertion failure'); }

            // CREATE
            Account acc = SmokeTestDataFactory.createAccount();
            System.assertNotEquals(null, acc.Id,
                'Account Id must be populated after insert');

            // READ — verify persisted field values
            Account queried = [
                SELECT Id, Name FROM Account WHERE Id = :acc.Id WITH SECURITY_ENFORCED LIMIT 1
            ];
            System.assert(queried.Name.startsWith('SMOKE_TEST'),
                'Account Name must have SMOKE_TEST prefix; got: ' + queried.Name);

            // UPDATE
            queried.Name = 'SMOKE_TEST Account Updated';
            update queried;

            // READ-AFTER-UPDATE — verify the change persisted
            Account updated = [
                SELECT Id, Name FROM Account WHERE Id = :queried.Id WITH SECURITY_ENFORCED LIMIT 1
            ];
            System.assertEquals('SMOKE_TEST Account Updated', updated.Name,
                'Account Name must reflect the update');

            // DELETE
            delete updated;

            // READ-AFTER-DELETE — must return 0 rows
            List<Account> gone = [
                SELECT Id FROM Account WHERE Id = :updated.Id WITH SECURITY_ENFORCED
            ];
            System.assertEquals(0, gone.size(),
                'Account must not be queryable after delete');

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
            'Validates Account CRUD operations: create, read-after-write, field update, delete',
            true,
            'Sales',
            10
        );
    }

    public GovernorBudgetConfig getGovernorBudget() {
        return new GovernorBudgetConfig(); // 5000ms CPU, 50 SOQL, 50 DML
    }

    // =========================================================================
    // Private helper
    // =========================================================================

    private static String cap(String s) {
        if (s == null) { return null; }
        return s.length() > MAX_ERROR_LEN ? s.substring(0, MAX_ERROR_LEN) : s;
    }
}
