/**
 * Smoke test scenario: Contact CRUD with parent Account relationship validation.
 *
 * Verifies create (with auto-created parent Account), AccountId relationship
 * persistence, Email field update, and delete on Contact records.
 */
public with sharing class ContactCrudScenario implements ISmokeTestScenario {

    public static final String SCENARIO_NAME = 'Contact_CRUD';
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

            // CREATE — factory auto-creates a parent Account when AccountId is absent
            Contact con = SmokeTestDataFactory.createContact();
            System.assertNotEquals(null, con.Id,
                'Contact Id must be populated after insert');
            System.assertNotEquals(null, con.AccountId,
                'Contact AccountId must be populated (factory creates parent Account)');

            // READ — verify relationship and name prefix
            Contact queried = [
                SELECT Id, LastName, AccountId, Email
                FROM Contact
                WHERE Id = :con.Id
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            System.assertNotEquals(null, queried.AccountId,
                'Contact AccountId must persist after insert');
            System.assert(queried.LastName.startsWith('SMOKE_TEST'),
                'Contact LastName must have SMOKE_TEST prefix; got: ' + queried.LastName);

            // UPDATE — change Email field
            queried.Email = 'smoke.test@example.invalid';
            update queried;

            // READ-AFTER-UPDATE
            Contact updated = [
                SELECT Id, Email FROM Contact WHERE Id = :queried.Id WITH SECURITY_ENFORCED LIMIT 1
            ];
            System.assertEquals('smoke.test@example.invalid', updated.Email,
                'Contact Email must reflect the update');

            // DELETE Contact (parent Account is left intact — belongs to the org)
            delete updated;

            // READ-AFTER-DELETE
            List<Contact> gone = [
                SELECT Id FROM Contact WHERE Id = :updated.Id WITH SECURITY_ENFORCED
            ];
            System.assertEquals(0, gone.size(),
                'Contact must not be queryable after delete');

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
            'Validates Contact CRUD with parent Account relationship: create, read, email update, delete',
            true,
            'Sales',
            20
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
