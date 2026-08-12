/**
 * Unit tests for SmokeTestDataFactory.
 *
 * Coverage targets per acceptance criteria:
 *   - Single-record creation with non-null Id for all 5 SObject types
 *   - Bulk creation returns requested count with unique names
 *   - Field override maps override defaults and leave unspecified defaults intact
 *   - Contact auto-creates parent Account when AccountId not provided
 *   - Contact with explicit AccountId does not create a second Account
 *   - Bulk contacts share one auto-created parent Account
 *   - Opportunity auto-creates parent Account and sets StageName/CloseDate/Amount defaults
 *   - SMOKE_TEST prefix on all name/subject/lastName fields
 *   - Count=0 returns empty list (no DML, no exception)
 *   - Null override map treated as empty
 *   - Counter produces unique names across consecutive calls in same transaction
 *   - Invalid field name in override map throws SmokeTestDataFactoryException with
 *     descriptive message including the offending field name
 *   - Lead conversion-readiness (required fields populated)
 */
@isTest
private class SmokeTestDataFactoryTest {

    // =========================================================================
    // Account tests
    // =========================================================================

    @isTest
    static void testCreateAccountSingle() {
        Test.startTest();
        Account acc = SmokeTestDataFactory.createAccount();
        Test.stopTest();

        System.assertNotEquals(null, acc.Id, 'Account must have Id after insert');
        System.assert(acc.Name.startsWith('SMOKE_TEST'), 'Account.Name must use SMOKE_TEST prefix');
    }

    @isTest
    static void testCreateAccountNullOverrideTreatedAsEmpty() {
        Test.startTest();
        Account acc = SmokeTestDataFactory.createAccount(null);
        Test.stopTest();

        System.assertNotEquals(null, acc.Id, 'Null override must not prevent successful insert');
        System.assert(acc.Name.startsWith('SMOKE_TEST'));
    }

    @isTest
    static void testCreateAccountWithOverride() {
        Test.startTest();
        Account acc = SmokeTestDataFactory.createAccount(new Map<String,Object>{
            'Name'        => 'SMOKE_TEST Override Account',
            'Description' => 'Test override description'
        });
        Test.stopTest();

        System.assertNotEquals(null, acc.Id);
        System.assertEquals('SMOKE_TEST Override Account', acc.Name,
            'Override Name must take precedence over factory default');
        System.assertEquals('Test override description', acc.Description,
            'Override Description must be applied');
    }

    @isTest
    static void testCreateAccountsZeroCount() {
        Test.startTest();
        List<Account> accs = SmokeTestDataFactory.createAccounts(0);
        Test.stopTest();

        System.assertEquals(0, accs.size(), 'Zero count must return empty list without DML');
    }

    @isTest
    static void testCreateAccountsNullCount() {
        Test.startTest();
        List<Account> accs = SmokeTestDataFactory.createAccounts(null);
        Test.stopTest();

        System.assertEquals(0, accs.size(), 'Null count must return empty list without DML');
    }

    @isTest
    static void testCreateAccountsBulk() {
        Test.startTest();
        List<Account> accs = SmokeTestDataFactory.createAccounts(5);
        Test.stopTest();

        System.assertEquals(5, accs.size(), 'Should create exactly 5 accounts');
        Set<String> names = new Set<String>();
        for (Account acc : accs) {
            System.assertNotEquals(null, acc.Id, 'Each bulk account must have Id');
            System.assert(acc.Name.startsWith('SMOKE_TEST'), 'Each account must have SMOKE_TEST prefix');
            names.add(acc.Name);
        }
        System.assertEquals(5, names.size(), 'Bulk account names must be unique');
    }

    @isTest
    static void testCreateAccountsBulkWithOverride() {
        Test.startTest();
        List<Account> accs = SmokeTestDataFactory.createAccounts(3, new Map<String,Object>{
            'BillingCountry' => 'US'
        });
        Test.stopTest();

        System.assertEquals(3, accs.size());
        for (Account acc : accs) {
            System.assertEquals('US', acc.BillingCountry,
                'Override field must apply to every bulk record');
            System.assert(acc.Name.startsWith('SMOKE_TEST'),
                'Default Name prefix must still apply despite override');
        }
    }

    // =========================================================================
    // Contact tests
    // =========================================================================

    @isTest
    static void testCreateContactAutoCreatesParentAccount() {
        Test.startTest();
        Contact con = SmokeTestDataFactory.createContact();
        Test.stopTest();

        System.assertNotEquals(null, con.Id, 'Contact must have Id after insert');
        System.assertNotEquals(null, con.AccountId,
            'Contact factory must auto-create parent Account when none provided');
        System.assert(con.LastName.startsWith('SMOKE_TEST'), 'LastName must use SMOKE_TEST prefix');
    }

    @isTest
    static void testCreateContactWithExplicitAccountId() {
        Account acc = SmokeTestDataFactory.createAccount();

        Test.startTest();
        Contact con = SmokeTestDataFactory.createContact(new Map<String,Object>{
            'AccountId' => acc.Id
        });
        Test.stopTest();

        System.assertEquals(acc.Id, con.AccountId,
            'Explicitly provided AccountId must be used — no auto-create');
        System.assertEquals(1, [SELECT COUNT() FROM Account],
            'Exactly one Account must exist — the explicitly created one');
    }

    @isTest
    static void testCreateContactWithOverride() {
        Test.startTest();
        Contact con = SmokeTestDataFactory.createContact(new Map<String,Object>{
            'LastName'  => 'SMOKE_TEST Override Last',
            'FirstName' => 'Override'
        });
        Test.stopTest();

        System.assertEquals('SMOKE_TEST Override Last', con.LastName,
            'Override LastName must take precedence');
        System.assertEquals('Override', con.FirstName, 'Override FirstName must be applied');
    }

    @isTest
    static void testCreateContactsZeroCount() {
        Test.startTest();
        List<Contact> cons = SmokeTestDataFactory.createContacts(0);
        Test.stopTest();

        System.assertEquals(0, cons.size(), 'Zero count must return empty list');
    }

    @isTest
    static void testCreateContactsBulkSharesSingleParentAccount() {
        Test.startTest();
        List<Contact> cons = SmokeTestDataFactory.createContacts(3);
        Test.stopTest();

        System.assertEquals(3, cons.size());
        Set<Id> accountIds = new Set<Id>();
        for (Contact con : cons) {
            System.assertNotEquals(null, con.Id);
            System.assertNotEquals(null, con.AccountId);
            System.assert(con.LastName.startsWith('SMOKE_TEST'));
            accountIds.add(con.AccountId);
        }
        System.assertEquals(1, accountIds.size(),
            'Bulk contacts must share one auto-created parent Account');
        System.assertEquals(1, [SELECT COUNT() FROM Account],
            'Only one Account should be created for bulk contacts');
    }

    @isTest
    static void testCreateContactsBulkWithExplicitAccountId() {
        Account acc = SmokeTestDataFactory.createAccount();

        Test.startTest();
        List<Contact> cons = SmokeTestDataFactory.createContacts(3, new Map<String,Object>{
            'AccountId' => acc.Id
        });
        Test.stopTest();

        System.assertEquals(3, cons.size());
        System.assertEquals(1, [SELECT COUNT() FROM Account],
            'Explicit AccountId must prevent auto-creation of a second Account');
        for (Contact con : cons) {
            System.assertEquals(acc.Id, con.AccountId, 'All contacts must link to explicit account');
        }
    }

    // =========================================================================
    // Opportunity tests
    // =========================================================================

    @isTest
    static void testCreateOpportunityAutoCreatesAccountSetsDefaults() {
        Test.startTest();
        Opportunity opp = SmokeTestDataFactory.createOpportunity();
        Test.stopTest();

        System.assertNotEquals(null, opp.Id, 'Opportunity must have Id after insert');
        System.assertNotEquals(null, opp.AccountId,
            'Opportunity factory must auto-create parent Account when none provided');
        System.assert(opp.Name.startsWith('SMOKE_TEST'), 'Name must use SMOKE_TEST prefix');
        System.assertEquals('Prospecting', opp.StageName,
            'StageName must default to Prospecting');
        System.assertEquals(Date.today().addDays(30), opp.CloseDate,
            'CloseDate must default to 30 days from today');
        System.assertEquals(10000.0, opp.Amount, 'Amount must default to 10000');
    }

    @isTest
    static void testCreateOpportunityWithOverride() {
        Test.startTest();
        Opportunity opp = SmokeTestDataFactory.createOpportunity(new Map<String,Object>{
            'StageName' => 'Closed Won',
            'Amount'    => 50000
        });
        Test.stopTest();

        System.assertNotEquals(null, opp.Id);
        System.assertEquals('Closed Won', opp.StageName, 'StageName override must be applied');
        System.assertEquals(50000.0, opp.Amount, 'Amount override must be applied');
        System.assertNotEquals(null, opp.AccountId, 'Auto-created AccountId must still be set');
    }

    @isTest
    static void testCreateOpportunitiesZeroCount() {
        Test.startTest();
        List<Opportunity> opps = SmokeTestDataFactory.createOpportunities(0);
        Test.stopTest();

        System.assertEquals(0, opps.size(), 'Zero count must return empty list');
    }

    @isTest
    static void testCreateOpportunitiesBulk() {
        Test.startTest();
        List<Opportunity> opps = SmokeTestDataFactory.createOpportunities(3);
        Test.stopTest();

        System.assertEquals(3, opps.size());
        Set<String> names = new Set<String>();
        for (Opportunity opp : opps) {
            System.assertNotEquals(null, opp.Id);
            System.assert(opp.Name.startsWith('SMOKE_TEST'));
            System.assertEquals('Prospecting', opp.StageName);
            names.add(opp.Name);
        }
        System.assertEquals(3, names.size(), 'Bulk opportunity names must be unique');
    }

    @isTest
    static void testCreateOpportunitiesBulkSharesSingleParentAccount() {
        Test.startTest();
        List<Opportunity> opps = SmokeTestDataFactory.createOpportunities(3);
        Test.stopTest();

        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : opps) {
            accountIds.add(opp.AccountId);
        }
        System.assertEquals(1, accountIds.size(),
            'Bulk opportunities must share one auto-created parent Account');
    }

    // =========================================================================
    // Case tests
    // =========================================================================

    @isTest
    static void testCreateCaseSingle() {
        Test.startTest();
        Case c = SmokeTestDataFactory.createCase();
        Test.stopTest();

        System.assertNotEquals(null, c.Id, 'Case must have Id after insert');
        System.assert(c.Subject.startsWith('SMOKE_TEST'), 'Subject must use SMOKE_TEST prefix');
        System.assertEquals('New', c.Status, 'Status must default to New');
        System.assertEquals('Web', c.Origin, 'Origin must default to Web');
    }

    @isTest
    static void testCreateCaseWithOverride() {
        Test.startTest();
        Case c = SmokeTestDataFactory.createCase(new Map<String,Object>{
            'Status'  => 'Working',
            'Subject' => 'SMOKE_TEST Override Case'
        });
        Test.stopTest();

        System.assertNotEquals(null, c.Id);
        System.assertEquals('Working', c.Status, 'Status override must be applied');
        System.assertEquals('SMOKE_TEST Override Case', c.Subject, 'Subject override must be applied');
        System.assertEquals('Web', c.Origin, 'Non-overridden Origin must remain at default');
    }

    @isTest
    static void testCreateCasesZeroCount() {
        Test.startTest();
        List<Case> cases = SmokeTestDataFactory.createCases(0);
        Test.stopTest();

        System.assertEquals(0, cases.size(), 'Zero count must return empty list');
    }

    @isTest
    static void testCreateCasesBulk() {
        Test.startTest();
        List<Case> cases = SmokeTestDataFactory.createCases(4);
        Test.stopTest();

        System.assertEquals(4, cases.size());
        Set<String> subjects = new Set<String>();
        for (Case c : cases) {
            System.assertNotEquals(null, c.Id);
            System.assert(c.Subject.startsWith('SMOKE_TEST'));
            subjects.add(c.Subject);
        }
        System.assertEquals(4, subjects.size(), 'Bulk case subjects must be unique');
    }

    // =========================================================================
    // Lead tests
    // =========================================================================

    @isTest
    static void testCreateLeadSingle() {
        Test.startTest();
        Lead l = SmokeTestDataFactory.createLead();
        Test.stopTest();

        System.assertNotEquals(null, l.Id, 'Lead must have Id after insert');
        System.assert(l.LastName.startsWith('SMOKE_TEST'), 'LastName must use SMOKE_TEST prefix');
        System.assertEquals('SMOKE_TEST Corp', l.Company, 'Company must default to SMOKE_TEST Corp');
        System.assertEquals('Open - Not Contacted', l.Status,
            'Status must default to Open - Not Contacted');
        System.assertEquals('Web', l.LeadSource, 'LeadSource must default to Web');
    }

    @isTest
    static void testCreateLeadWithOverride() {
        Test.startTest();
        Lead l = SmokeTestDataFactory.createLead(new Map<String,Object>{
            'Company'  => 'SMOKE_TEST Override Corp',
            'LastName' => 'SMOKE_TEST Override Lead',
            'Status'   => 'Working - Contacted'
        });
        Test.stopTest();

        System.assertNotEquals(null, l.Id);
        System.assertEquals('SMOKE_TEST Override Corp', l.Company, 'Company override must be applied');
        System.assertEquals('SMOKE_TEST Override Lead', l.LastName, 'LastName override must be applied');
        System.assertEquals('Working - Contacted', l.Status, 'Status override must be applied');
        System.assertEquals('Web', l.LeadSource, 'Non-overridden LeadSource must remain at default');
    }

    @isTest
    static void testCreateLeadsZeroCount() {
        Test.startTest();
        List<Lead> leads = SmokeTestDataFactory.createLeads(0);
        Test.stopTest();

        System.assertEquals(0, leads.size(), 'Zero count must return empty list');
    }

    @isTest
    static void testCreateLeadsBulk() {
        Test.startTest();
        List<Lead> leads = SmokeTestDataFactory.createLeads(3);
        Test.stopTest();

        System.assertEquals(3, leads.size());
        Set<String> lastNames = new Set<String>();
        for (Lead l : leads) {
            System.assertNotEquals(null, l.Id);
            System.assert(l.LastName.startsWith('SMOKE_TEST'));
            lastNames.add(l.LastName);
        }
        System.assertEquals(3, lastNames.size(), 'Bulk lead last names must be unique');
    }

    @isTest
    static void testLeadConversionReadiness() {
        Lead l = SmokeTestDataFactory.createLead();

        System.assert(String.isNotBlank(l.LastName), 'LastName required for lead conversion');
        System.assert(String.isNotBlank(l.Company),  'Company required for lead conversion');
        System.assert(String.isNotBlank(l.Status),   'Status required for lead conversion');
    }

    // =========================================================================
    // Cross-cutting: SMOKE_TEST prefix on all types
    // =========================================================================

    @isTest
    static void testSmokeTestPrefixOnAllTypes() {
        Test.startTest();
        Account     acc = SmokeTestDataFactory.createAccount();
        Contact     con = SmokeTestDataFactory.createContact();
        Opportunity opp = SmokeTestDataFactory.createOpportunity();
        Case        c   = SmokeTestDataFactory.createCase();
        Lead        l   = SmokeTestDataFactory.createLead();
        Test.stopTest();

        System.assert(acc.Name.startsWith('SMOKE_TEST'),     'Account.Name must start with SMOKE_TEST');
        System.assert(con.LastName.startsWith('SMOKE_TEST'), 'Contact.LastName must start with SMOKE_TEST');
        System.assert(opp.Name.startsWith('SMOKE_TEST'),     'Opportunity.Name must start with SMOKE_TEST');
        System.assert(c.Subject.startsWith('SMOKE_TEST'),    'Case.Subject must start with SMOKE_TEST');
        System.assert(l.LastName.startsWith('SMOKE_TEST'),   'Lead.LastName must start with SMOKE_TEST');
    }

    @isTest
    static void testCounterProducesUniqueNamesAcrossConsecutiveCalls() {
        Account acc1 = SmokeTestDataFactory.createAccount();
        Account acc2 = SmokeTestDataFactory.createAccount();
        Account acc3 = SmokeTestDataFactory.createAccount();

        System.assertNotEquals(acc1.Name, acc2.Name,
            'Counter must increment so consecutive calls produce unique names');
        System.assertNotEquals(acc2.Name, acc3.Name);
        System.assertNotEquals(acc1.Name, acc3.Name);
    }

    // =========================================================================
    // Error handling: invalid field name
    // =========================================================================

    @isTest
    static void testInvalidFieldNameThrowsFactoryExceptionForAccount() {
        SmokeTestDataFactory.SmokeTestDataFactoryException thrown;
        Test.startTest();
        try {
            SmokeTestDataFactory.createAccount(new Map<String,Object>{
                'NonExistentField__xyz' => 'bad value'
            });
        } catch (SmokeTestDataFactory.SmokeTestDataFactoryException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, thrown,
            'Invalid field name must throw SmokeTestDataFactoryException');
        System.assert(thrown.getMessage().contains('NonExistentField__xyz'),
            'Exception message must identify the invalid field name');
        System.assert(thrown.getMessage().contains('Account'),
            'Exception message must identify the SObject type');
    }

    @isTest
    static void testInvalidFieldNameThrowsFactoryExceptionForLead() {
        SmokeTestDataFactory.SmokeTestDataFactoryException thrown;
        Test.startTest();
        try {
            SmokeTestDataFactory.createLead(new Map<String,Object>{
                'BadLeadField__zzz' => 'bad value'
            });
        } catch (SmokeTestDataFactory.SmokeTestDataFactoryException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, thrown,
            'Invalid field name on Lead must throw SmokeTestDataFactoryException');
        System.assert(thrown.getMessage().contains('BadLeadField__zzz'),
            'Exception message must include the offending field name');
    }
}
