/**
 * Manual verification script: SmokeTest Integration User — Tooling API access check.
 *
 * Run via: sf apex run --file scripts/verify-integration-user.apex --target-org <alias>
 *
 * Verifies:
 *   1. The integration user exists in the org.
 *   2. SmokeTest_API_User permission set is assigned.
 *   3. The Tooling API SecurityHealthCheck query succeeds for the user.
 *
 * Expected output (success):
 *   [VERIFY] Integration user found: smoketest-integration@<domain>.com (Id: 005...)
 *   [VERIFY] SmokeTest_API_User permission set is assigned.
 *   [VERIFY] Tooling API SecurityHealthCheck query succeeded. Score: 85
 *   [VERIFY] All integration user checks passed.
 *
 * Note: The Tooling API callout runs under the CURRENT running user's session (admin),
 * not as the integration user. To test the integration user's direct Tooling API access,
 * use the curl command documented in docs/integration-user-setup.md Section 5.
 */

// =========================================================================
// Step 1: Find the integration user
// =========================================================================
List<User> users = [
    SELECT Id, Username, IsActive, ProfileId, Profile.Name
    FROM User
    WHERE Username LIKE 'smoketest-integration@%'
    AND IsActive = true
    ORDER BY CreatedDate DESC
    LIMIT 5
];

if (users.isEmpty()) {
    System.debug('ERROR: No active integration user found matching smoketest-integration@*. '
        + 'Run: new SmokeTestPostInstallHandler().onInstall(null); or create the user manually.');
    // Exit early
    return;
}

User integrationUser = users[0];
System.debug('[VERIFY] Integration user found: ' + integrationUser.Username
    + ' (Id: ' + integrationUser.Id + ')'
    + ' Profile: ' + integrationUser.Profile.Name);

// =========================================================================
// Step 2: Verify SmokeTest_API_User permission set assignment
// =========================================================================
List<PermissionSetAssignment> psas = [
    SELECT Id, PermissionSet.Name
    FROM PermissionSetAssignment
    WHERE AssigneeId = :integrationUser.Id
    AND PermissionSet.Name = 'SmokeTest_API_User'
    LIMIT 1
];

if (psas.isEmpty()) {
    System.debug('WARNING: SmokeTest_API_User permission set is NOT assigned to '
        + integrationUser.Username
        + '. Assign it via: sf org assign permset --name SmokeTest_API_User --on-behalf-of '
        + integrationUser.Username);
} else {
    System.debug('[VERIFY] SmokeTest_API_User permission set is assigned.');
}

// =========================================================================
// Step 3: Verify ViewSetup permission on the integration profile
// =========================================================================
List<PermissionSet> profilePsets = [
    SELECT Id, PermissionsViewSetup, PermissionsApiEnabled
    FROM PermissionSet
    WHERE ProfileId = :integrationUser.ProfileId
    AND IsOwnedByProfile = true
    LIMIT 1
];

if (!profilePsets.isEmpty()) {
    PermissionSet ps = profilePsets[0];
    System.debug('[VERIFY] Profile permissions — '
        + 'ApiEnabled: ' + ps.PermissionsApiEnabled
        + ', ViewSetup: ' + ps.PermissionsViewSetup);
    if (!ps.PermissionsApiEnabled) {
        System.debug('WARNING: ApiEnabled is false on the integration profile. '
            + 'The user cannot make REST or Tooling API calls.');
    }
    if (!ps.PermissionsViewSetup) {
        System.debug('WARNING: ViewSetup is false on the integration profile. '
            + 'SecurityHealthCheck Tooling API queries will fail with INSUFFICIENT_ACCESS.');
    }
} else {
    System.debug('WARNING: Could not retrieve profile permissions for ' + integrationUser.Profile.Name);
}

// =========================================================================
// Step 4: Tooling API SecurityHealthCheck query
// =========================================================================
String sessionId = UserInfo.getSessionId();
String instanceUrl = URL.getSalesforceBaseUrl().toExternalForm();
String endpoint = instanceUrl
    + '/services/data/v60.0/tooling/query/?q=SELECT+Id,Score+FROM+SecurityHealthCheck';

HttpRequest req = new HttpRequest();
req.setEndpoint(endpoint);
req.setMethod('GET');
req.setHeader('Authorization', 'Bearer ' + sessionId);
req.setHeader('Content-Type', 'application/json');

try {
    HttpResponse res = new Http().send(req);
    if (res.getStatusCode() == 200) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> records = (List<Object>) body.get('records');
        if (records != null && !records.isEmpty()) {
            Map<String, Object> rec = (Map<String, Object>) records[0];
            System.debug('[VERIFY] Tooling API SecurityHealthCheck query succeeded. Score: ' + rec.get('Score'));
        } else {
            System.debug('[VERIFY] Tooling API responded with 200 but no records.');
        }
    } else {
        System.debug('ERROR: Tooling API returned HTTP ' + res.getStatusCode()
            + '. Body: ' + res.getBody());
    }
} catch (Exception e) {
    System.debug('ERROR: Tooling API callout failed: ' + e.getMessage()
        + '. Ensure callouts are allowed (Remote Site Settings or Named Credentials) '
        + 'and the running user has ViewSetup permission.');
}

// =========================================================================
// Step 5: Summary
// =========================================================================
if (!psas.isEmpty()
    && !profilePsets.isEmpty()
    && profilePsets[0].PermissionsApiEnabled
    && profilePsets[0].PermissionsViewSetup) {
    System.debug('[VERIFY] All integration user checks passed.');
} else {
    System.debug('[VERIFY] One or more checks require attention — review WARNING messages above.');
}
