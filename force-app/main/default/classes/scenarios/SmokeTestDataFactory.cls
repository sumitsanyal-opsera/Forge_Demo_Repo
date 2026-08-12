/**
 * Centralized factory for creating isolated test records with the SMOKE_TEST prefix.
 *
 * Design principles:
 *   - Every factory method inserts the created record(s) and returns them with Ids populated.
 *   - All name/subject fields use the SMOKE_TEST prefix for post-execution leak detection.
 *   - An auto-incrementing static counter ensures unique names within a single transaction.
 *   - Each method accepts an optional Map<String,Object> for field overrides that take
 *     precedence over defaults. Null override map is treated as empty (no throw).
 *   - Parent records (Account for Contact, Opportunity) are auto-created when not supplied.
 *   - DmlException propagates to the calling scenario — factory does not swallow DML errors.
 *   - SObjectException from invalid override field names is caught and re-thrown with the
 *     offending field name included for diagnostics.
 *
 * Bulk limit: single-batch insert; relies on Salesforce DML row governor (10,000 rows max).
 * Passing large counts may approach per-transaction DML row budgets shared with other
 * operations in the scenario. The field override map allows callers to satisfy custom
 * required fields present in specific org configurations.
 */
public with sharing class SmokeTestDataFactory {

    public class SmokeTestDataFactoryException extends Exception {}

    @TestVisible private static Integer counter = 1;

    // =========================================================================
    // Account
    // =========================================================================

    public static Account createAccount() {
        return createAccount(null);
    }

    public static Account createAccount(Map<String,Object> overrides) {
        Map<String,Object> defaults = new Map<String,Object>{
            'Name' => 'SMOKE_TEST Account ' + zeroPad(counter++)
        };
        Account acc = new Account();
        applyFields(acc, mergeDefaults(defaults, overrides));
        insert acc;
        return acc;
    }

    public static List<Account> createAccounts(Integer count) {
        return createAccounts(count, null);
    }

    public static List<Account> createAccounts(Integer count, Map<String,Object> overrides) {
        if (count == null || count <= 0) {
            return new List<Account>();
        }
        List<Account> records = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            Map<String,Object> defaults = new Map<String,Object>{
                'Name' => 'SMOKE_TEST Account ' + zeroPad(counter++)
            };
            Account acc = new Account();
            applyFields(acc, mergeDefaults(defaults, overrides));
            records.add(acc);
        }
        insert records;
        return records;
    }

    // =========================================================================
    // Contact
    // =========================================================================

    public static Contact createContact() {
        return createContact(null);
    }

    public static Contact createContact(Map<String,Object> overrides) {
        Map<String,Object> callOverrides = (overrides != null)
            ? new Map<String,Object>(overrides)
            : new Map<String,Object>();
        if (!callOverrides.containsKey('AccountId')) {
            callOverrides.put('AccountId', createAccount().Id);
        }
        Map<String,Object> defaults = new Map<String,Object>{
            'LastName'  => 'SMOKE_TEST Contact ' + zeroPad(counter++),
            'FirstName' => 'Test'
        };
        Contact con = new Contact();
        applyFields(con, mergeDefaults(defaults, callOverrides));
        insert con;
        return con;
    }

    public static List<Contact> createContacts(Integer count) {
        return createContacts(count, null);
    }

    public static List<Contact> createContacts(Integer count, Map<String,Object> overrides) {
        if (count == null || count <= 0) {
            return new List<Contact>();
        }
        Map<String,Object> baseOverrides = (overrides != null)
            ? new Map<String,Object>(overrides)
            : new Map<String,Object>();
        if (!baseOverrides.containsKey('AccountId')) {
            baseOverrides.put('AccountId', createAccount().Id);
        }
        List<Contact> records = new List<Contact>();
        for (Integer i = 0; i < count; i++) {
            Map<String,Object> defaults = new Map<String,Object>{
                'LastName'  => 'SMOKE_TEST Contact ' + zeroPad(counter++),
                'FirstName' => 'Test'
            };
            Contact con = new Contact();
            applyFields(con, mergeDefaults(defaults, baseOverrides));
            records.add(con);
        }
        insert records;
        return records;
    }

    // =========================================================================
    // Opportunity
    // =========================================================================

    public static Opportunity createOpportunity() {
        return createOpportunity(null);
    }

    public static Opportunity createOpportunity(Map<String,Object> overrides) {
        Map<String,Object> callOverrides = (overrides != null)
            ? new Map<String,Object>(overrides)
            : new Map<String,Object>();
        if (!callOverrides.containsKey('AccountId')) {
            callOverrides.put('AccountId', createAccount().Id);
        }
        Map<String,Object> defaults = new Map<String,Object>{
            'Name'      => 'SMOKE_TEST Opportunity ' + zeroPad(counter++),
            'StageName' => 'Prospecting',
            'CloseDate' => Date.today().addDays(30),
            'Amount'    => 10000
        };
        Opportunity opp = new Opportunity();
        applyFields(opp, mergeDefaults(defaults, callOverrides));
        insert opp;
        return opp;
    }

    public static List<Opportunity> createOpportunities(Integer count) {
        return createOpportunities(count, null);
    }

    public static List<Opportunity> createOpportunities(Integer count, Map<String,Object> overrides) {
        if (count == null || count <= 0) {
            return new List<Opportunity>();
        }
        Map<String,Object> baseOverrides = (overrides != null)
            ? new Map<String,Object>(overrides)
            : new Map<String,Object>();
        if (!baseOverrides.containsKey('AccountId')) {
            baseOverrides.put('AccountId', createAccount().Id);
        }
        List<Opportunity> records = new List<Opportunity>();
        for (Integer i = 0; i < count; i++) {
            Map<String,Object> defaults = new Map<String,Object>{
                'Name'      => 'SMOKE_TEST Opportunity ' + zeroPad(counter++),
                'StageName' => 'Prospecting',
                'CloseDate' => Date.today().addDays(30),
                'Amount'    => 10000
            };
            Opportunity opp = new Opportunity();
            applyFields(opp, mergeDefaults(defaults, baseOverrides));
            records.add(opp);
        }
        insert records;
        return records;
    }

    // =========================================================================
    // Case
    // =========================================================================

    public static Case createCase() {
        return createCase(null);
    }

    public static Case createCase(Map<String,Object> overrides) {
        Map<String,Object> defaults = new Map<String,Object>{
            'Subject' => 'SMOKE_TEST Case ' + zeroPad(counter++),
            'Status'  => 'New',
            'Origin'  => 'Web'
        };
        Case c = new Case();
        applyFields(c, mergeDefaults(defaults, overrides));
        insert c;
        return c;
    }

    public static List<Case> createCases(Integer count) {
        return createCases(count, null);
    }

    public static List<Case> createCases(Integer count, Map<String,Object> overrides) {
        if (count == null || count <= 0) {
            return new List<Case>();
        }
        List<Case> records = new List<Case>();
        for (Integer i = 0; i < count; i++) {
            Map<String,Object> defaults = new Map<String,Object>{
                'Subject' => 'SMOKE_TEST Case ' + zeroPad(counter++),
                'Status'  => 'New',
                'Origin'  => 'Web'
            };
            Case c = new Case();
            applyFields(c, mergeDefaults(defaults, overrides));
            records.add(c);
        }
        insert records;
        return records;
    }

    // =========================================================================
    // Lead
    // =========================================================================

    public static Lead createLead() {
        return createLead(null);
    }

    public static Lead createLead(Map<String,Object> overrides) {
        Map<String,Object> defaults = new Map<String,Object>{
            'LastName'   => 'SMOKE_TEST Lead ' + zeroPad(counter++),
            'Company'    => 'SMOKE_TEST Corp',
            'Status'     => 'Open - Not Contacted',
            'LeadSource' => 'Web'
        };
        Lead l = new Lead();
        applyFields(l, mergeDefaults(defaults, overrides));
        insert l;
        return l;
    }

    public static List<Lead> createLeads(Integer count) {
        return createLeads(count, null);
    }

    public static List<Lead> createLeads(Integer count, Map<String,Object> overrides) {
        if (count == null || count <= 0) {
            return new List<Lead>();
        }
        List<Lead> records = new List<Lead>();
        for (Integer i = 0; i < count; i++) {
            Map<String,Object> defaults = new Map<String,Object>{
                'LastName'   => 'SMOKE_TEST Lead ' + zeroPad(counter++),
                'Company'    => 'SMOKE_TEST Corp',
                'Status'     => 'Open - Not Contacted',
                'LeadSource' => 'Web'
            };
            Lead l = new Lead();
            applyFields(l, mergeDefaults(defaults, overrides));
            records.add(l);
        }
        insert records;
        return records;
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private static Map<String,Object> mergeDefaults(Map<String,Object> defaults, Map<String,Object> overrides) {
        Map<String,Object> result = new Map<String,Object>(defaults);
        if (overrides != null) {
            result.putAll(overrides);
        }
        return result;
    }

    private static void applyFields(SObject record, Map<String,Object> fields) {
        for (String fieldName : fields.keySet()) {
            try {
                record.put(fieldName, fields.get(fieldName));
            } catch (SObjectException e) {
                throw new SmokeTestDataFactoryException(
                    'Invalid field "' + fieldName + '" on ' +
                    record.getSObjectType().getDescribe().getName() + ': ' + e.getMessage(),
                    e
                );
            }
        }
    }

    private static String zeroPad(Integer n) {
        String s = String.valueOf(n);
        while (s.length() < 3) {
            s = '0' + s;
        }
        return s;
    }
}
