/**
 * Smoke test scenario: Opportunity CRUD with stage progression validation.
 *
 * Verifies create, Amount persistence across stage changes (Prospecting →
 * Qualification → Closed Won), and delete on Opportunity records.
 */
public with sharing class OpportunityCrudScenario implements ISmokeTestScenario {

    public static final String SCENARIO_NAME = 'Opportunity_Pipeline';
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

            // CREATE — factory defaults: StageName='Prospecting', Amount=10000, CloseDate=today+30
            Opportunity opp = SmokeTestDataFactory.createOpportunity();
            System.assertNotEquals(null, opp.Id,
                'Opportunity Id must be populated after insert');

            // READ — verify Amount and initial stage
            Opportunity queried = [
                SELECT Id, Name, StageName, Amount
                FROM Opportunity
                WHERE Id = :opp.Id
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            System.assertEquals(10000, queried.Amount,
                'Opportunity Amount must be 10000 after create');
            System.assertEquals('Prospecting', queried.StageName,
                'Opportunity StageName must be Prospecting initially');

            // UPDATE — advance to Qualification; verify Amount still persists
            queried.StageName = 'Qualification';
            update queried;

            Opportunity atQualification = [
                SELECT Id, StageName, Amount FROM Opportunity
                WHERE Id = :queried.Id WITH SECURITY_ENFORCED LIMIT 1
            ];
            System.assertEquals('Qualification', atQualification.StageName,
                'Opportunity StageName must be Qualification after first update');
            System.assertEquals(10000, atQualification.Amount,
                'Opportunity Amount must persist through stage progression');

            // UPDATE — advance to Closed Won
            atQualification.StageName = 'Closed Won';
            update atQualification;

            Opportunity atClosedWon = [
                SELECT Id, StageName, Amount FROM Opportunity
                WHERE Id = :atQualification.Id WITH SECURITY_ENFORCED LIMIT 1
            ];
            System.assertEquals('Closed Won', atClosedWon.StageName,
                'Opportunity StageName must be Closed Won after second update');
            System.assertEquals(10000, atClosedWon.Amount,
                'Opportunity Amount must persist at Closed Won stage');

            // DELETE
            delete atClosedWon;

            // READ-AFTER-DELETE
            List<Opportunity> gone = [
                SELECT Id FROM Opportunity WHERE Id = :atClosedWon.Id WITH SECURITY_ENFORCED
            ];
            System.assertEquals(0, gone.size(),
                'Opportunity must not be queryable after delete');

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
            'Validates Opportunity stage pipeline: create, stage progression Prospecting→Qualification→Closed Won, Amount persistence, delete',
            true,
            'Sales',
            30
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
