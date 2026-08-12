public with sharing class SmokeTestDashboardController {

    private static final String PERM_ADMIN  = 'SmokeTest_Admin';
    private static final String PERM_VIEWER = 'SmokeTest_Dashboard_Viewer';

    /**
     * Returns the running user's permission level for the Smoke Test Center.
     * Server-side permission check per OWASP A01 — never client-side.
     * permissionLevel: 'admin' | 'viewer' | 'none'
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> checkUserPermissions() {
        Id userId = UserInfo.getUserId();
        Boolean isAdmin  = false;
        Boolean isViewer = false;

        List<PermissionSetAssignment> assignments = [
            SELECT PermissionSet.Name
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
            AND PermissionSet.Name IN :new Set<String>{ PERM_ADMIN, PERM_VIEWER }
            WITH SECURITY_ENFORCED
        ];

        for (PermissionSetAssignment psa : assignments) {
            if (psa.PermissionSet.Name == PERM_ADMIN) {
                isAdmin = true;
            } else if (psa.PermissionSet.Name == PERM_VIEWER) {
                isViewer = true;
            }
        }

        String permissionLevel;
        if (isAdmin) {
            permissionLevel = 'admin';
        } else if (isViewer) {
            permissionLevel = 'viewer';
        } else {
            permissionLevel = 'none';
        }

        return new Map<String, Object>{
            'permissionLevel' => permissionLevel,
            'isAdmin'  => isAdmin,
            'isViewer' => isViewer || isAdmin
        };
    }
}
