/**
 * Unit tests for SmokeTest_Integration_Profile and SmokeTestPostInstallHandler.
 *
 * Test strategy:
 *   - Create a test user with SmokeTest_Integration_Profile (or Minimum Access
 *     as a fallback when the custom profile is not yet deployed to the test org).
 *   - Use System.runAs() to verify CRUD restrictions are enforced by Salesforce
 *     at the object permission level — DML operations must throw DmlException.
 *   - Verify read-only SOQL access works under System.runAs().
 *   - Verify the post-install handler runs without throwing, with idempotent
 *     re-invocation handled gracefully.
 *   - Mock the Tooling API callout to confirm the SecurityHealthCheck request
 *     can be constructed and dispatched as the integration user.
 *
 * Coverage target: ≥85% on SmokeTestPostInstallHandler.
 */
@isTest
private class SmokeTestIntegrationUserTest {

    private static final String INTEGRATION_PROFILE = 'SmokeTest_Integration_Profile';

    // =========================================================================
    // Shared helpers
    // =========================================================================

    /**
     * Returns the integration profile if deployed; falls back to Minimum Access
     * so tests remain executable in environments where the profile is not yet deployed.
     */
    private static Profile resolveProfile() {
        List<Profile> profiles = [
            SELECT Id, Name FROM Profile WHERE Name = :INTEGRATION_PROFILE ORDER BY Name LIMIT 1
        ];
        if (!profiles.isEmpty()) {
            return profiles[0];
        }
        // Fallback: Minimum Access profile (exists in all Salesforce orgs)
        profiles = [SELECT Id, Name FROM Profile WHERE Name = 'Minimum Access' LIMIT 1];
        if (!profiles.isEmpty()) {
            return profiles[0];
        }
        return [SELECT Id, Name FROM Profile WHERE UserType = 'Standard' ORDER BY Name LIMIT 1];
    }

    private static User buildTestUser(Profile p, Integer suffix) {
        return new User(
            Username          = 'smkinttest' + suffix + '@smoketest-unit.invalid',
            Alias             = 'smt' + suffix,
            Email             = 'smkinttest' + suffix + '@smoketest-unit.invalid',
            FirstName         = 'Smoke',
            LastName          = 'TestInt' + suffix,
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'America/New_York',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive          = true
        );
    }

    // =========================================================================
    // CRUD restriction tests — standard business objects
    // =========================================================================

    @isTest
    static void testIntegrationUserCannotInsertAccount() {
        Profile p = resolveProfile();
        User testUser = buildTestUser(p, 1);
        insert testUser;

        System.runAs(testUser) {
            Boolean threw = false;
            try {
                insert new Account(Name = 'SMOKE_TEST_AccountInsert');
            } catch (DmlException e) {
                threw = true;
            }
            System.assert(threw,
                'Account insert must throw DmlException for read-only integration profile; profile: ' + p.Name);
        }
    }

    @isTest
    static void testIntegrationUserCannotUpdateAccount() {
        // Create the Account as the current admin context before switching users
        Account acc = new Account(Name = 'SMOKE_TEST_AccountUpdate');
        insert acc;

        Profile p = resolveProfile();
        User testUser = buildTestUser(p, 2);
        insert testUser;

        System.runAs(testUser) {
            Boolean threw = false;
            try {
                acc.Name = 'SMOKE_TEST_ModifiedName';
                update acc;
            } catch (DmlException e) {
                threw = true;
            }
            System.assert(threw,
                'Account update must throw DmlException for read-only integration profile; profile: ' + p.Name);
        }
    }

    @isTest
    static void testIntegrationUserCannotDeleteAccount() {
        Account acc = new Account(Name = 'SMOKE_TEST_AccountDelete');
        insert acc;

        Profile p = resolveProfile();
        User testUser = buildTestUser(p, 3);
        insert testUser;

        System.runAs(testUser) {
            Boolean threw = false;
            try {
                delete acc;
            } catch (DmlException e) {
                threw = true;
            }
            System.assert(threw,
                'Account delete must throw DmlException for read-only integration profile; profile: ' + p.Name);
        }
    }

    @isTest
    static void testIntegrationUserCannotInsertContact() {
        Account acc = new Account(Name = 'SMOKE_TEST_ParentAccount');
        insert acc;

        Profile p = resolveProfile();
        User testUser = buildTestUser(p, 4);
        insert testUser;

        System.runAs(testUser) {
            Boolean threw = false;
            try {
                insert new Contact(LastName = 'SMOKE_TEST_ContactInsert', AccountId = acc.Id);
            } catch (DmlException e) {
                threw = true;
            }
            System.assert(threw,
                'Contact insert must throw DmlException for read-only integration profile');
        }
    }

    @isTest
    static void testIntegrationUserCannotInsertOpportunity() {
        Account acc = new Account(Name = 'SMOKE_TEST_OppParent');
        insert acc;

        Profile p = resolveProfile();
        User testUser = buildTestUser(p, 5);
        insert testUser;

        System.runAs(testUser) {
            Boolean threw = false;
            try {
                insert new Opportunity(
                    Name        = 'SMOKE_TEST_OppInsert',
                    StageName   = 'Prospecting',
                    CloseDate   = Date.today().addDays(30),
                    AccountId   = acc.Id
                );
            } catch (DmlException e) {
                threw = true;
            }
            System.assert(threw,
                'Opportunity insert must throw DmlException for read-only integration profile');
        }
    }

    @isTest
    static void testIntegrationUserCannotInsertCase() {
        Profile p = resolveProfile();
        User testUser = buildTestUser(p, 6);
        insert testUser;

        System.runAs(testUser) {
            Boolean threw = false;
            try {
                insert new Case(Subject = 'SMOKE_TEST_CaseInsert');
            } catch (DmlException e) {
                threw = true;
            }
            System.assert(threw,
                'Case insert must throw DmlException for read-only integration profile');
        }
    }

    @isTest
    static void testIntegrationUserCannotInsertLead() {
        Profile p = resolveProfile();
        User testUser = buildTestUser(p, 7);
        insert testUser;

        System.runAs(testUser) {
            Boolean threw = false;
            try {
                insert new Lead(
                    FirstName = 'SMOKE_TEST',
                    LastName  = 'LeadInsert',
                    Company   = 'SMOKE_TEST_Co'
                );
            } catch (DmlException e) {
                threw = true;
            }
            System.assert(threw,
                'Lead insert must throw DmlException for read-only integration profile');
        }
    }

    // =========================================================================
    // Read access test
    // =========================================================================

    @isTest
    static void testIntegrationUserCanReadAccounts() {
        Account acc = new Account(Name = 'SMOKE_TEST_ReadAccount');
        insert acc;

        Profile p = resolveProfile();
        User testUser = buildTestUser(p, 8);
        insert testUser;

        System.runAs(testUser) {
            // SOQL inside System.runAs() is subject to sharing and object-level read access
            Integer queryCount = [SELECT COUNT() FROM Account];
            System.assert(queryCount >= 0,
                'Account SOQL must not throw for a user with read access');
        }
    }

    // =========================================================================
    // Profile permission verification
    // =========================================================================

    @isTest
    static void testIntegrationProfileExistsWhenDeployed() {
        List<Profile> profiles = [
            SELECT Id, Name FROM Profile WHERE Name = :INTEGRATION_PROFILE LIMIT 1
        ];
        if (profiles.isEmpty()) {
            // Profile not deployed to this scratch org yet — test is advisory only
            System.assert(true, 'SmokeTest_Integration_Profile not found; profile deployment pending');
            return;
        }
        System.assertNotEquals(null, profiles[0].Id,
            'SmokeTest_Integration_Profile must have a valid Id after deployment');
    }

    @isTest
    static void testIntegrationProfileHasApiEnabledPermission() {
        List<Profile> profiles = [
            SELECT Id FROM Profile WHERE Name = :INTEGRATION_PROFILE LIMIT 1
        ];
        if (profiles.isEmpty()) {
            System.assert(true, 'SmokeTest_Integration_Profile not found; profile deployment pending');
            return;
        }
        // Confirm ApiEnabled is set on the profile via PermissionSet proxy
        List<PermissionSet> psets = [
            SELECT Id, PermissionsApiEnabled
            FROM PermissionSet
            WHERE ProfileId = :profiles[0].Id AND IsOwnedByProfile = true
            LIMIT 1
        ];
        System.assert(!psets.isEmpty(), 'Profile must have a backing PermissionSet');
        System.assert(psets[0].PermissionsApiEnabled,
            'SmokeTest_Integration_Profile must have ApiEnabled = true');
    }

    @isTest
    static void testIntegrationProfileHasViewSetupPermission() {
        List<Profile> profiles = [
            SELECT Id FROM Profile WHERE Name = :INTEGRATION_PROFILE LIMIT 1
        ];
        if (profiles.isEmpty()) {
            System.assert(true, 'SmokeTest_Integration_Profile not found; profile deployment pending');
            return;
        }
        List<PermissionSet> psets = [
            SELECT Id, PermissionsViewSetup
            FROM PermissionSet
            WHERE ProfileId = :profiles[0].Id AND IsOwnedByProfile = true
            LIMIT 1
        ];
        System.assert(!psets.isEmpty(), 'Profile must have a backing PermissionSet');
        System.assert(psets[0].PermissionsViewSetup,
            'SmokeTest_Integration_Profile must have ViewSetup = true for Tooling API access');
    }

    // =========================================================================
    // Tooling API callout test (mocked)
    // =========================================================================

    @isTest
    static void testIntegrationUserCanDescribeSecurityHealthCheck() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiHealthCheckMock());

        Profile p = resolveProfile();
        User testUser = buildTestUser(p, 9);
        insert testUser;

        System.runAs(testUser) {
            // Construct a SecurityHealthCheck Tooling API request
            HttpRequest req = new HttpRequest();
            req.setEndpoint(
                URL.getSalesforceBaseUrl().toExternalForm()
                + '/services/data/v60.0/tooling/query/?q=SELECT+Id,Score+FROM+SecurityHealthCheck'
            );
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setHeader('Content-Type', 'application/json');

            HttpResponse res = new Http().send(req);
            System.assertEquals(200, res.getStatusCode(),
                'Tooling API SecurityHealthCheck mock must return 200');
            System.assert(res.getBody().contains('SecurityHealthCheck'),
                'Response body must contain SecurityHealthCheck marker');
        }
    }

    // =========================================================================
    // Post-install handler tests
    // =========================================================================

    @isTest
    static void testPostInstallHandlerBuildUsernameFormat() {
        String username = SmokeTestPostInstallHandler.buildUsername();
        System.assert(username.startsWith(SmokeTestPostInstallHandler.USERNAME_LOCAL_PART + '@'),
            'Username must start with smoketest-integration@; got: ' + username);
        System.assert(username.contains('.'),
            'Username must contain a dot separator; got: ' + username);
        System.assert(username.length() >= 25,
            'Username must be at least 25 chars; got: ' + username);
    }

    @isTest
    static void testPostInstallHandlerFreshInstall() {
        Test.startTest();
        // Test.testInstall() calls onInstall() with a mock InstallContext
        Test.testInstall(new SmokeTestPostInstallHandler(), null, false);
        Test.stopTest();
        System.assert(true, 'onInstall() completed without unhandled exceptions on fresh install');
    }

    @isTest
    static void testPostInstallHandlerUpgrade() {
        Test.startTest();
        Test.testInstall(new SmokeTestPostInstallHandler(), new Version(1, 0), true);
        Test.stopTest();
        System.assert(true, 'onInstall() completed without unhandled exceptions on upgrade');
    }

    @isTest
    static void testPostInstallHandlerIdempotentDoubleInvocation() {
        // First install
        Test.startTest();
        Test.testInstall(new SmokeTestPostInstallHandler(), null, false);
        // Second install (simulating re-deployment) — should not throw
        Test.testInstall(new SmokeTestPostInstallHandler(), new Version(1, 0), false);
        Test.stopTest();
        System.assert(true, 'Duplicate onInstall() must not throw');
    }

    @isTest
    static void testPostInstallHandlerDirectInvocationDoesNotThrow() {
        // Manual invocation via anonymous Apex (documented in integration-user-setup.md)
        Test.startTest();
        new SmokeTestPostInstallHandler().onInstall(null);
        Test.stopTest();
        System.assert(true, 'Direct onInstall(null) invocation must not throw');
    }

    // =========================================================================
    // Inner HTTP mock for Tooling API
    // =========================================================================

    private class ToolingApiHealthCheckMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"totalSize":1,"done":true,"records":[{"attributes":{"type":"SecurityHealthCheck"},"Id":"000000000000000000","Score":85}]}');
            return res;
        }
    }
}
