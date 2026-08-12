/**
 * Post-install handler for the SmokeTestCenter unlocked package.
 *
 * Executed automatically when the package is installed or upgraded via
 * Salesforce packaging. Creates the dedicated read-only integration service
 * account user and assigns the SmokeTest_API_User permission set.
 *
 * Failure policy: all exceptions are caught and logged via System.debug so
 * that an error during user creation never blocks package installation.
 * If automated creation fails, follow docs/integration-user-setup.md for
 * manual setup steps.
 *
 * Manual invocation (scratch orgs / non-packaged deployments):
 *   new SmokeTestPostInstallHandler().onInstall(null);
 */
global class SmokeTestPostInstallHandler implements InstallHandler {

    @TestVisible static final String INTEGRATION_PROFILE_NAME = 'SmokeTest_Integration_Profile';
    @TestVisible static final String PERMISSION_SET_NAME      = 'SmokeTest_API_User';
    @TestVisible static final String USERNAME_LOCAL_PART      = 'smoketest-integration';

    // =========================================================================
    // InstallHandler entry point
    // =========================================================================

    global void onInstall(InstallContext context) {
        try {
            String username = buildUsername();
            createIntegrationUser(username);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[SmokeTestPostInstallHandler] User creation failed — manual setup required. '
                + 'See docs/integration-user-setup.md. Error: ' + e.getMessage());
        }
    }

    // =========================================================================
    // Username construction
    // =========================================================================

    /**
     * Builds the integration user username following the convention
     * smoketest-integration@<orgdomain>.com, with a sandbox suffix appended
     * when running in a sandbox environment to ensure global uniqueness.
     */
    @TestVisible
    static String buildUsername() {
        String rawDomain = UserInfo.getOrganizationName()
            .toLowerCase()
            .trim()
            .replaceAll('[^a-z0-9]', '-')
            .replaceAll('-{2,}', '-')
            .removeStart('-')
            .removeEnd('-');

        if (String.isBlank(rawDomain)) {
            // Fall back to org ID prefix when org name sanitizes to nothing
            rawDomain = UserInfo.getOrganizationId().substring(0, 15).toLowerCase();
        }

        String base = USERNAME_LOCAL_PART + '@' + rawDomain + '.com';

        // Append sandbox suffix to maintain global username uniqueness
        try {
            List<Organization> orgs = [SELECT IsSandbox FROM Organization LIMIT 1];
            if (!orgs.isEmpty() && orgs[0].IsSandbox) {
                // Derive sandbox name from the current user's username suffix
                // Convention: user@domain.sandboxname  (suffix after last dot ≠ TLD)
                String currentUser = UserInfo.getUserName();
                Integer lastDot    = currentUser.lastIndexOf('.');
                if (lastDot > 0) {
                    String possibleSuffix = currentUser.substring(lastDot + 1);
                    Set<String> tlds = new Set<String>{'com', 'net', 'org', 'io', 'gov', 'edu'};
                    if (!tlds.contains(possibleSuffix.toLowerCase())) {
                        base = base.removeEnd('.com') + '.' + possibleSuffix;
                    }
                }
            }
        } catch (Exception e) {
            // Non-critical; continue with base username
            System.debug(LoggingLevel.WARN,
                '[SmokeTestPostInstallHandler] Could not determine sandbox context: ' + e.getMessage());
        }
        return base;
    }

    // =========================================================================
    // User creation
    // =========================================================================

    private static void createIntegrationUser(String username) {
        // Idempotent: if user already exists, ensure permission set is assigned
        List<User> existing = [SELECT Id FROM User WHERE Username = :username LIMIT 1];
        if (!existing.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                '[SmokeTestPostInstallHandler] Integration user already exists: '
                + username + '. Skipping creation; ensuring permission set assignment.');
            assignPermissionSet(existing[0].Id);
            return;
        }

        List<Profile> profiles = [
            SELECT Id FROM Profile WHERE Name = :INTEGRATION_PROFILE_NAME LIMIT 1
        ];
        if (profiles.isEmpty()) {
            throw new SetupException(
                'Profile "' + INTEGRATION_PROFILE_NAME + '" not found. '
                + 'Deploy the SmokeTestCenter package metadata before running the post-install handler, '
                + 'or create the integration user manually (see docs/integration-user-setup.md).');
        }

        User integrationUser = new User(
            Username         = username,
            Alias            = 'smkint',
            Email            = username,
            FirstName        = 'SmokeTest',
            LastName         = 'Integration',
            ProfileId        = profiles[0].Id,
            TimeZoneSidKey   = 'America/New_York',
            LocaleSidKey     = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive         = true
        );

        try {
            insert integrationUser;
        } catch (DmlException e) {
            String msg = e.getMessage();
            if (msg.contains('DUPLICATE_USERNAME') || msg.contains('USERNAME_ALREADY_USED')) {
                System.debug(LoggingLevel.WARN,
                    '[SmokeTestPostInstallHandler] Duplicate username "' + username
                    + '". The integration user already exists globally. Skipping creation.');
                return;
            }
            if (msg.contains('LICENSE_LIMIT_EXCEEDED')) {
                System.debug(LoggingLevel.ERROR,
                    '[SmokeTestPostInstallHandler] License limit exceeded. '
                    + 'Resolution options: (1) Free a Salesforce license, '
                    + '(2) Request a Salesforce Integration license for this service account, '
                    + '(3) Assign SmokeTest_API_User permission set to an existing service account user manually. '
                    + 'See docs/integration-user-setup.md.');
                return;
            }
            throw e;
        }

        assignPermissionSet(integrationUser.Id);
    }

    // =========================================================================
    // Permission set assignment
    // =========================================================================

    private static void assignPermissionSet(Id userId) {
        List<PermissionSet> psets = [
            SELECT Id FROM PermissionSet
            WHERE Name = :PERMISSION_SET_NAME AND IsOwnedByProfile = false
            LIMIT 1
        ];
        if (psets.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                '[SmokeTestPostInstallHandler] Permission set "' + PERMISSION_SET_NAME
                + '" not found. Assign manually: Setup > Users > [User] > Permission Set Assignments.');
            return;
        }

        // Idempotent: skip if already assigned
        List<PermissionSetAssignment> already = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetId = :psets[0].Id
            LIMIT 1
        ];
        if (!already.isEmpty()) {
            return;
        }

        try {
            insert new PermissionSetAssignment(
                AssigneeId      = userId,
                PermissionSetId = psets[0].Id
            );
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR,
                '[SmokeTestPostInstallHandler] Could not assign permission set "' + PERMISSION_SET_NAME
                + '": ' + e.getMessage());
        }
    }

    // =========================================================================
    // Custom exception
    // =========================================================================

    public class SetupException extends Exception {}
}
