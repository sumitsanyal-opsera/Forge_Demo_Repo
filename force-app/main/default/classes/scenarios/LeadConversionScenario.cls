/**
 * Smoke test scenario: Lead creation and full conversion workflow.
 *
 * Verifies that a Lead can be created, converted to Account + Contact +
 * Opportunity, and that all three resulting records exist after conversion.
 * Queries the org's converted LeadStatus dynamically rather than hardcoding
 * a value to avoid failures in orgs with custom status configurations.
 */
public with sharing class LeadConversionScenario implements ISmokeTestScenario {

    public static final String SCENARIO_NAME = 'Lead_Conversion';
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

            // RESOLVE CONVERTED LEAD STATUS — dynamic query to avoid hardcoded values
            List<LeadStatus> convertedStatuses = [
                SELECT MasterLabel
                FROM LeadStatus
                WHERE IsConverted = true
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (convertedStatuses.isEmpty()) {
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'CONFIGURATION_ERROR',
                    'No converted LeadStatus found in org. At least one LeadStatus with IsConverted=true must exist.');
            }
            String convertedStatus = convertedStatuses[0].MasterLabel;

            // CREATE LEAD
            Lead lead = SmokeTestDataFactory.createLead();
            System.assertNotEquals(null, lead.Id,
                'Lead Id must be populated after insert');

            // CONVERT LEAD
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(lead.Id);
            lc.setConvertedStatus(convertedStatus);
            lc.setDoNotCreateOpportunity(false);

            Database.LeadConvertResult lcr = Database.convertLead(lc);

            if (!lcr.isSuccess()) {
                List<String> errMessages = new List<String>();
                for (Database.Error err : lcr.getErrors()) {
                    errMessages.add(err.getMessage());
                }
                return ScenarioResult.failure(SCENARIO_NAME, System.currentTimeMillis() - start,
                    'CONVERSION_FAILED',
                    cap('Lead conversion failed: ' + String.join(errMessages, '; ')));
            }

            // VERIFY RESULTING RECORDS
            Id accountId     = lcr.getAccountId();
            Id contactId     = lcr.getContactId();
            Id opportunityId = lcr.getOpportunityId();

            System.assertNotEquals(null, accountId,
                'Lead conversion must produce an Account');
            System.assertNotEquals(null, contactId,
                'Lead conversion must produce a Contact');
            System.assertNotEquals(null, opportunityId,
                'Lead conversion must produce an Opportunity');

            // READ CONVERTED RECORDS
            List<Account> accounts = [
                SELECT Id FROM Account WHERE Id = :accountId WITH SECURITY_ENFORCED LIMIT 1
            ];
            System.assertEquals(1, accounts.size(),
                'Converted Account must be queryable');

            List<Contact> contacts = [
                SELECT Id FROM Contact WHERE Id = :contactId WITH SECURITY_ENFORCED LIMIT 1
            ];
            System.assertEquals(1, contacts.size(),
                'Converted Contact must be queryable');

            List<Opportunity> opportunities = [
                SELECT Id FROM Opportunity WHERE Id = :opportunityId WITH SECURITY_ENFORCED LIMIT 1
            ];
            System.assertEquals(1, opportunities.size(),
                'Converted Opportunity must be queryable');

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
            'Validates Lead conversion workflow: create Lead, convert to Account + Contact + Opportunity, verify all three records exist',
            true,
            'Sales',
            50
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
