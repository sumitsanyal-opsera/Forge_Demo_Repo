/**
 * Integration test: validates the three-tier RBAC access matrix for
 * SmokeTest_Dashboard_Viewer, SmokeTest_Admin, and SmokeTest_API_User permission sets.
 *
 * PREREQUISITE: All three permission sets must be deployed to the scratch org before
 * running these tests. Permission set definitions are in:
 *   force-app/main/default/permissionsets/SmokeTest_*.permissionset-meta.xml
 *
 * Known Salesforce platform behavior: users with "Modify All Data" system permission
 * (e.g., System Administrator profile) can bypass object-level security regardless
 * of permission set assignments. This test class uses "Minimum Access - Salesforce"
 * profile specifically to avoid this bypass.
 *
 * Schema.describe() calls within System.runAs() blocks reflect the running user's
 * FLS and CRUD permissions as granted by their profile + permission sets.
 */
@isTest
private class SmokeTestPermissionSetTest {

    // =========================================================================
    // Test data setup
    // =========================================================================

    @TestSetup
    static void makeData() {
        Profile minAccessProfile = [
            SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1
        ];

        Long ts = DateTime.now().getTime();

        User dashboardUser = new User(
            FirstName         = 'Dashboard',
            LastName          = 'Viewer',
            Email             = 'smoketest.dashboard@example.test',
            Username          = 'smoketest.dashboard.' + ts + '@example.test',
            Alias             = 'sdv',
            ProfileId         = minAccessProfile.Id,
            TimeZoneSidKey    = 'America/New_York',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        User adminUser = new User(
            FirstName         = 'Smoke',
            LastName          = 'Admin',
            Email             = 'smoketest.admin@example.test',
            Username          = 'smoketest.admin.' + (ts + 1) + '@example.test',
            Alias             = 'sadm',
            ProfileId         = minAccessProfile.Id,
            TimeZoneSidKey    = 'America/New_York',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        User apiUser = new User(
            FirstName         = 'API',
            LastName          = 'User',
            Email             = 'smoketest.api@example.test',
            Username          = 'smoketest.api.' + (ts + 2) + '@example.test',
            Alias             = 'sapi',
            ProfileId         = minAccessProfile.Id,
            TimeZoneSidKey    = 'America/New_York',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        insert new List<User>{ dashboardUser, adminUser, apiUser };

        Map<String, Id> psMap = new Map<String, Id>();
        for (PermissionSet ps : [
            SELECT Id, Name FROM PermissionSet
            WHERE Name IN ('SmokeTest_Dashboard_Viewer', 'SmokeTest_Admin', 'SmokeTest_API_User')
        ]) {
            psMap.put(ps.Name, ps.Id);
        }

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        if (psMap.containsKey('SmokeTest_Dashboard_Viewer')) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId     = dashboardUser.Id,
                PermissionSetId = psMap.get('SmokeTest_Dashboard_Viewer')
            ));
        }
        if (psMap.containsKey('SmokeTest_Admin')) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId     = adminUser.Id,
                PermissionSetId = psMap.get('SmokeTest_Admin')
            ));
        }
        if (psMap.containsKey('SmokeTest_API_User')) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId     = apiUser.Id,
                PermissionSetId = psMap.get('SmokeTest_API_User')
            ));
        }

        if (!assignments.isEmpty()) {
            insert assignments;
        }
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private static User getDashboardUser() {
        return [SELECT Id FROM User WHERE Email = 'smoketest.dashboard@example.test' LIMIT 1];
    }

    private static User getAdminUser() {
        return [SELECT Id FROM User WHERE Email = 'smoketest.admin@example.test' LIMIT 1];
    }

    private static User getApiUser() {
        return [SELECT Id FROM User WHERE Email = 'smoketest.api@example.test' LIMIT 1];
    }

    // =========================================================================
    // Permission set existence
    // =========================================================================

    @isTest
    static void testPermissionSetsExist() {
        List<PermissionSet> psList = [
            SELECT Id, Name FROM PermissionSet
            WHERE Name IN ('SmokeTest_Dashboard_Viewer', 'SmokeTest_Admin', 'SmokeTest_API_User')
        ];

        Set<String> found = new Set<String>();
        for (PermissionSet ps : psList) {
            found.add(ps.Name);
        }

        System.assert(found.contains('SmokeTest_Dashboard_Viewer'),
            'SmokeTest_Dashboard_Viewer permission set must be deployed');
        System.assert(found.contains('SmokeTest_Admin'),
            'SmokeTest_Admin permission set must be deployed');
        System.assert(found.contains('SmokeTest_API_User'),
            'SmokeTest_API_User permission set must be deployed');
    }

    // =========================================================================
    // Dashboard Viewer — positive: can read Internal-tier objects
    // =========================================================================

    @isTest
    static void testDashboardViewerCanReadExecution() {
        User u = getDashboardUser();
        System.runAs(u) {
            System.assert(Schema.SObjectType.SmokeTestExecution__c.isAccessible(),
                'Dashboard Viewer must have read access to SmokeTestExecution__c');
        }
    }

    @isTest
    static void testDashboardViewerCanReadResult() {
        User u = getDashboardUser();
        System.runAs(u) {
            System.assert(Schema.SObjectType.SmokeTestResult__c.isAccessible(),
                'Dashboard Viewer must have read access to SmokeTestResult__c');
        }
    }

    @isTest
    static void testDashboardViewerExecutionStatusFieldReadable() {
        User u = getDashboardUser();
        System.runAs(u) {
            Schema.DescribeFieldResult dfr =
                SmokeTestExecution__c.Status__c.getDescribe();
            System.assert(dfr.isAccessible(),
                'Dashboard Viewer must have read FLS on SmokeTestExecution__c.Status__c');
            System.assert(!dfr.isUpdateable(),
                'Dashboard Viewer must NOT have edit FLS on SmokeTestExecution__c.Status__c');
        }
    }

    // =========================================================================
    // Dashboard Viewer — negative: cannot access Confidential-tier objects
    // =========================================================================

    @isTest
    static void testDashboardViewerCannotAccessSecurityScore() {
        User u = getDashboardUser();
        System.runAs(u) {
            System.assert(!Schema.SObjectType.SmokeTestSecurityScore__c.isAccessible(),
                'Dashboard Viewer must NOT have read access to SmokeTestSecurityScore__c (Confidential)');
        }
    }

    @isTest
    static void testDashboardViewerCannotAccessAuditLog() {
        User u = getDashboardUser();
        System.runAs(u) {
            System.assert(!Schema.SObjectType.SmokeTestAuditLog__c.isAccessible(),
                'Dashboard Viewer must NOT have read access to SmokeTestAuditLog__c (Confidential)');
        }
    }

    @isTest
    static void testDashboardViewerSecurityScoreRawResponseInaccessible() {
        User u = getDashboardUser();
        System.runAs(u) {
            Schema.DescribeFieldResult dfr =
                SmokeTestSecurityScore__c.RawResponse__c.getDescribe();
            System.assert(!dfr.isAccessible(),
                'Dashboard Viewer must NOT have FLS access to SmokeTestSecurityScore__c.RawResponse__c');
        }
    }

    @isTest
    static void testDashboardViewerSecurityEnforcedBlocksSecurityScore() {
        User u = getDashboardUser();
        System.runAs(u) {
            Boolean exceptionThrown = false;
            try {
                List<SmokeTestSecurityScore__c> scores = [
                    SELECT Id FROM SmokeTestSecurityScore__c WITH SECURITY_ENFORCED LIMIT 1
                ];
            } catch (Exception e) {
                exceptionThrown = true;
            }
            System.assert(exceptionThrown,
                'WITH SECURITY_ENFORCED must throw for Dashboard Viewer accessing SmokeTestSecurityScore__c');
        }
    }

    @isTest
    static void testDashboardViewerSecurityEnforcedBlocksAuditLog() {
        User u = getDashboardUser();
        System.runAs(u) {
            Boolean exceptionThrown = false;
            try {
                List<SmokeTestAuditLog__c> logs = [
                    SELECT Id FROM SmokeTestAuditLog__c WITH SECURITY_ENFORCED LIMIT 1
                ];
            } catch (Exception e) {
                exceptionThrown = true;
            }
            System.assert(exceptionThrown,
                'WITH SECURITY_ENFORCED must throw for Dashboard Viewer accessing SmokeTestAuditLog__c');
        }
    }

    // =========================================================================
    // Admin — positive: full CRUD on Internal, Read/Create on Confidential
    // =========================================================================

    @isTest
    static void testAdminCanReadAllObjects() {
        User u = getAdminUser();
        System.runAs(u) {
            System.assert(Schema.SObjectType.SmokeTestExecution__c.isAccessible(),
                'Admin must read SmokeTestExecution__c');
            System.assert(Schema.SObjectType.SmokeTestResult__c.isAccessible(),
                'Admin must read SmokeTestResult__c');
            System.assert(Schema.SObjectType.SmokeTestSecurityScore__c.isAccessible(),
                'Admin must read SmokeTestSecurityScore__c (Confidential access granted)');
            System.assert(Schema.SObjectType.SmokeTestAuditLog__c.isAccessible(),
                'Admin must read SmokeTestAuditLog__c (Confidential access granted)');
        }
    }

    @isTest
    static void testAdminHasFullCRUDOnExecution() {
        User u = getAdminUser();
        System.runAs(u) {
            Schema.DescribeSObjectResult dsr = Schema.SObjectType.SmokeTestExecution__c;
            System.assert(dsr.isCreateable(), 'Admin must create SmokeTestExecution__c');
            System.assert(dsr.isUpdateable(), 'Admin must update SmokeTestExecution__c');
            System.assert(dsr.isDeletable(), 'Admin must delete SmokeTestExecution__c');
        }
    }

    @isTest
    static void testAdminHasReadOnlyOnAuditLog() {
        User u = getAdminUser();
        System.runAs(u) {
            Schema.DescribeSObjectResult dsr = Schema.SObjectType.SmokeTestAuditLog__c;
            System.assert(dsr.isAccessible(),
                'Admin must read SmokeTestAuditLog__c');
            System.assert(!dsr.isUpdateable(),
                'Admin must NOT update SmokeTestAuditLog__c (read-only at permission set level)');
            System.assert(!dsr.isDeletable(),
                'Admin must NOT delete SmokeTestAuditLog__c (read-only at permission set level)');
        }
    }

    @isTest
    static void testAdminSecurityScoreRawResponseAccessible() {
        User u = getAdminUser();
        System.runAs(u) {
            Schema.DescribeFieldResult dfr =
                SmokeTestSecurityScore__c.RawResponse__c.getDescribe();
            System.assert(dfr.isAccessible(),
                'Admin must have FLS access to SmokeTestSecurityScore__c.RawResponse__c');
        }
    }

    @isTest
    static void testAdminScoreDeltaReadableNotEditable() {
        User u = getAdminUser();
        System.runAs(u) {
            Schema.DescribeFieldResult dfr =
                SmokeTestSecurityScore__c.ScoreDelta__c.getDescribe();
            System.assert(dfr.isAccessible(),
                'Admin must read SmokeTestSecurityScore__c.ScoreDelta__c (formula field)');
            System.assert(!dfr.isUpdateable(),
                'ScoreDelta__c is a formula field and must never be editable');
        }
    }

    @isTest
    static void testAdminAuditLogFieldsReadableNotEditable() {
        User u = getAdminUser();
        System.runAs(u) {
            Schema.DescribeFieldResult dfr =
                SmokeTestAuditLog__c.IPAddress__c.getDescribe();
            System.assert(dfr.isAccessible(),
                'Admin must read SmokeTestAuditLog__c.IPAddress__c');
            System.assert(!dfr.isUpdateable(),
                'Admin must NOT edit SmokeTestAuditLog__c.IPAddress__c (immutability enforced)');
        }
    }

    // =========================================================================
    // API User — positive: Read/Create on Internal
    // =========================================================================

    @isTest
    static void testApiUserCanReadExecution() {
        User u = getApiUser();
        System.runAs(u) {
            System.assert(Schema.SObjectType.SmokeTestExecution__c.isAccessible(),
                'API User must read SmokeTestExecution__c');
        }
    }

    @isTest
    static void testApiUserCanCreateExecution() {
        User u = getApiUser();
        System.runAs(u) {
            System.assert(Schema.SObjectType.SmokeTestExecution__c.isCreateable(),
                'API User must create SmokeTestExecution__c');
        }
    }

    @isTest
    static void testApiUserCannotEditOrDeleteExecution() {
        User u = getApiUser();
        System.runAs(u) {
            Schema.DescribeSObjectResult dsr = Schema.SObjectType.SmokeTestExecution__c;
            System.assert(!dsr.isUpdateable(),
                'API User must NOT update SmokeTestExecution__c');
            System.assert(!dsr.isDeletable(),
                'API User must NOT delete SmokeTestExecution__c');
        }
    }

    // =========================================================================
    // API User — negative: cannot access Confidential-tier objects
    // =========================================================================

    @isTest
    static void testApiUserCannotAccessSecurityScore() {
        User u = getApiUser();
        System.runAs(u) {
            System.assert(!Schema.SObjectType.SmokeTestSecurityScore__c.isAccessible(),
                'API User must NOT have access to SmokeTestSecurityScore__c');
        }
    }

    @isTest
    static void testApiUserCannotAccessAuditLog() {
        User u = getApiUser();
        System.runAs(u) {
            System.assert(!Schema.SObjectType.SmokeTestAuditLog__c.isAccessible(),
                'API User must NOT have access to SmokeTestAuditLog__c');
        }
    }

    @isTest
    static void testApiUserSecurityEnforcedBlocksAuditLog() {
        User u = getApiUser();
        System.runAs(u) {
            Boolean exceptionThrown = false;
            try {
                List<SmokeTestAuditLog__c> logs = [
                    SELECT Id FROM SmokeTestAuditLog__c WITH SECURITY_ENFORCED LIMIT 1
                ];
            } catch (Exception e) {
                exceptionThrown = true;
            }
            System.assert(exceptionThrown,
                'WITH SECURITY_ENFORCED must throw for API User accessing SmokeTestAuditLog__c');
        }
    }

    @isTest
    static void testApiUserSecurityEnforcedBlocksSecurityScore() {
        User u = getApiUser();
        System.runAs(u) {
            Boolean exceptionThrown = false;
            try {
                List<SmokeTestSecurityScore__c> scores = [
                    SELECT Id FROM SmokeTestSecurityScore__c WITH SECURITY_ENFORCED LIMIT 1
                ];
            } catch (Exception e) {
                exceptionThrown = true;
            }
            System.assert(exceptionThrown,
                'WITH SECURITY_ENFORCED must throw for API User accessing SmokeTestSecurityScore__c');
        }
    }
}
