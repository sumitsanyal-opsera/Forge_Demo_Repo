@isTest
private class SmokeTestDashboardControllerTest {

    @TestSetup
    static void setup() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];

        List<User> users = new List<User>{
            makeUser('smokeadm',  'Admin SmokeTest',   p.Id),
            makeUser('smokevwr',  'Viewer SmokeTest',  p.Id),
            makeUser('smokenone', 'NoPerm SmokeTest',  p.Id)
        };
        insert users;

        PermissionSet adminPs  = [SELECT Id FROM PermissionSet WHERE Name = 'SmokeTest_Admin' LIMIT 1];
        PermissionSet viewerPs = [SELECT Id FROM PermissionSet WHERE Name = 'SmokeTest_Dashboard_Viewer' LIMIT 1];

        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = users[0].Id, PermissionSetId = adminPs.Id),
            new PermissionSetAssignment(AssigneeId = users[1].Id, PermissionSetId = viewerPs.Id)
        };
    }

    private static User makeUser(String alias, String lastName, Id profileId) {
        String uid = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
            FirstName         = 'Smoke',
            LastName          = lastName,
            Username          = alias + '.' + uid + '@smoketest.example.com',
            Email             = alias + '@smoketest.example.com',
            Alias             = alias.left(8),
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = profileId
        );
    }

    @isTest
    static void testAdminUser_ReturnsAdminPermissionLevel() {
        User adminUser = [SELECT Id FROM User WHERE LastName = 'Admin SmokeTest' LIMIT 1];

        Map<String, Object> result;
        System.runAs(adminUser) {
            Test.startTest();
            result = SmokeTestDashboardController.checkUserPermissions();
            Test.stopTest();
        }

        System.assertEquals('admin', (String) result.get('permissionLevel'),
            'Admin user must get permissionLevel=admin');
        System.assertEquals(true, (Boolean) result.get('isAdmin'),
            'isAdmin must be true for SmokeTest_Admin permission set holder');
        System.assertEquals(true, (Boolean) result.get('isViewer'),
            'isViewer must be true for admin (admin implies viewer access)');
    }

    @isTest
    static void testViewerUser_ReturnsViewerPermissionLevel() {
        User viewerUser = [SELECT Id FROM User WHERE LastName = 'Viewer SmokeTest' LIMIT 1];

        Map<String, Object> result;
        System.runAs(viewerUser) {
            Test.startTest();
            result = SmokeTestDashboardController.checkUserPermissions();
            Test.stopTest();
        }

        System.assertEquals('viewer', (String) result.get('permissionLevel'),
            'Viewer user must get permissionLevel=viewer');
        System.assertEquals(false, (Boolean) result.get('isAdmin'),
            'isAdmin must be false for viewer-only user');
        System.assertEquals(true, (Boolean) result.get('isViewer'),
            'isViewer must be true for SmokeTest_Dashboard_Viewer holder');
    }

    @isTest
    static void testNoPermissionUser_ReturnsNonePermissionLevel() {
        User noPermUser = [SELECT Id FROM User WHERE LastName = 'NoPerm SmokeTest' LIMIT 1];

        Map<String, Object> result;
        System.runAs(noPermUser) {
            Test.startTest();
            result = SmokeTestDashboardController.checkUserPermissions();
            Test.stopTest();
        }

        System.assertEquals('none', (String) result.get('permissionLevel'),
            'User with no permission set must get permissionLevel=none');
        System.assertEquals(false, (Boolean) result.get('isAdmin'));
        System.assertEquals(false, (Boolean) result.get('isViewer'));
    }

    @isTest
    static void testBothPermSets_AdminTakesPrecedence() {
        User adminUser = [SELECT Id FROM User WHERE LastName = 'Admin SmokeTest' LIMIT 1];
        PermissionSet viewerPs = [SELECT Id FROM PermissionSet WHERE Name = 'SmokeTest_Dashboard_Viewer' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = adminUser.Id, PermissionSetId = viewerPs.Id);

        Map<String, Object> result;
        System.runAs(adminUser) {
            Test.startTest();
            result = SmokeTestDashboardController.checkUserPermissions();
            Test.stopTest();
        }

        System.assertEquals('admin', (String) result.get('permissionLevel'),
            'When both Admin and Viewer are assigned, Admin must take precedence');
        System.assertEquals(true, (Boolean) result.get('isAdmin'));
        System.assertEquals(true, (Boolean) result.get('isViewer'));
    }

    @isTest
    static void testReturnedMapContainsAllExpectedKeys() {
        Map<String, Object> result = SmokeTestDashboardController.checkUserPermissions();

        System.assertNotEquals(null, result, 'Result map must not be null');
        System.assert(result.containsKey('permissionLevel'), 'Result must contain permissionLevel');
        System.assert(result.containsKey('isAdmin'),         'Result must contain isAdmin');
        System.assert(result.containsKey('isViewer'),        'Result must contain isViewer');
    }
}
