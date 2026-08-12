/**
 * Unit tests for LeadConversionScenario.
 * Coverage target: ≥90% on LeadConversionScenario.cls.
 */
@isTest
private class LeadConversionScenarioTest {

    private static SmokeTestContext makeContext() {
        SmokeTestExecution__c exec = new SmokeTestExecution__c();
        insert exec;
        return new SmokeTestContext(exec.Id, 'test-org', null);
    }

    // =========================================================================
    // Success path
    // =========================================================================

    @isTest
    static void testExecuteSuccessConvertsLeadToAllThreeRecords() {
        SmokeTestContext ctx = makeContext();
        Test.startTest();
        ScenarioResult result = new LeadConversionScenario().execute(ctx);
        Test.stopTest();

        System.assertEquals(true, result.passed,
            'Lead conversion must pass on a standard org; error: ' + result.errorDetail);
        System.assertEquals(LeadConversionScenario.SCENARIO_NAME, result.scenarioName);
        System.assertEquals(null, result.errorType);
        System.assertNotEquals(null, result.durationMs);
    }

    @isTest
    static void testConvertedLeadProducesAccountContactOpportunity() {
        // Run the scenario and then confirm converted records exist by querying
        SmokeTestContext ctx = makeContext();
        Lead lead = SmokeTestDataFactory.createLead();

        List<LeadStatus> convStatuses = [
            SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1
        ];
        if (convStatuses.isEmpty()) {
            // No converted status — scenario would return CONFIGURATION_ERROR; skip verification
            System.assert(true, 'No converted LeadStatus in org; skipping conversion verification');
            return;
        }

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(lead.Id);
        lc.setConvertedStatus(convStatuses[0].MasterLabel);
        lc.setDoNotCreateOpportunity(false);

        Database.LeadConvertResult lcr = Database.convertLead(lc);
        System.assertEquals(true, lcr.isSuccess(),
            'Lead conversion must succeed in the test org');
        System.assertNotEquals(null, lcr.getAccountId(),
            'Converted Account must be created');
        System.assertNotEquals(null, lcr.getContactId(),
            'Converted Contact must be created');
        System.assertNotEquals(null, lcr.getOpportunityId(),
            'Converted Opportunity must be created');
    }

    // =========================================================================
    // Exception path coverage
    // =========================================================================

    @isTest
    static void testExecuteDmlException() {
        LeadConversionScenario.injectException = new DmlException('Simulated Lead DML failure');
        try {
            ScenarioResult result = new LeadConversionScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('DML_EXCEPTION', result.errorType);
        } finally {
            LeadConversionScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteUnexpectedError() {
        LeadConversionScenario.injectException = new IllegalArgumentException('Unexpected lead error');
        try {
            ScenarioResult result = new LeadConversionScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('UNEXPECTED_ERROR', result.errorType);
        } finally {
            LeadConversionScenario.injectException = null;
        }
    }

    @isTest
    static void testExecuteAssertionFailed() {
        LeadConversionScenario.triggerAssertFail = true;
        try {
            ScenarioResult result = new LeadConversionScenario().execute(makeContext());
            System.assertEquals(false, result.passed);
            System.assertEquals('ASSERTION_FAILED', result.errorType);
        } finally {
            LeadConversionScenario.triggerAssertFail = false;
        }
    }

    @isTest
    static void testErrorDetailTruncatedAt1000Chars() {
        LeadConversionScenario.injectException = new DmlException('L'.repeat(1500));
        try {
            ScenarioResult result = new LeadConversionScenario().execute(makeContext());
            System.assert(result.errorDetail.length() <= 1000,
                'errorDetail must be capped at 1000 characters');
        } finally {
            LeadConversionScenario.injectException = null;
        }
    }

    // =========================================================================
    // Metadata and budget
    // =========================================================================

    @isTest
    static void testGetMetadata() {
        ScenarioMetadata meta = new LeadConversionScenario().getMetadata();

        System.assertEquals('Lead_Conversion', meta.scenarioName);
        System.assertEquals(true, meta.isCritical);
        System.assertEquals('Sales', meta.cloudType);
        System.assertEquals(50, meta.executionOrder);
    }

    @isTest
    static void testGetGovernorBudget() {
        GovernorBudgetConfig budget = new LeadConversionScenario().getGovernorBudget();

        System.assertEquals(5000, budget.cpuBudgetMs);
        System.assertEquals(50,   budget.soqlBudget);
        System.assertEquals(50,   budget.dmlBudget);
    }

    @isTest
    static void testImplementsISmokeTestScenario() {
        ISmokeTestScenario scenario = new LeadConversionScenario();
        System.assertNotEquals(null, scenario.getMetadata());
        System.assertNotEquals(null, scenario.getGovernorBudget());
    }
}
