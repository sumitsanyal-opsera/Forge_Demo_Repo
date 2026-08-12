/**
 * AuraEnabled Apex controller for the securityHealthCard LWC.
 *
 * Returns the most recent SmokeTestSecurityScore__c record for display
 * in the security health gauge component. This data is classified as
 * Confidential — only users with the SmokeTest_Admin permission set
 * may access it. The method enforces this check server-side so that
 * even direct API calls are blocked for unauthorised users.
 */
public with sharing class SmokeTestSecurityController {

    /**
     * Returns the latest SmokeTestSecurityScore__c record, or null if none exists.
     * Throws AuraHandledException for non-admin users.
     */
    @AuraEnabled(cacheable=true)
    public static SmokeTestSecurityScore__c getLatestSecurityScore() {
        if (!hasAdminPermission()) {
            throw new AuraHandledException(
                'Access denied: SmokeTest_Admin permission set required to view security scores');
        }

        List<SmokeTestSecurityScore__c> scores = [
            SELECT Id,
                   PreDeploymentScore__c,
                   PostDeploymentScore__c,
                   ScoreDelta__c,
                   ThresholdStatus__c,
                   ThresholdMet__c,
                   AbsoluteThreshold__c,
                   RelativeThreshold__c,
                   RiskCategories__c,
                   CheckedAt__c
            FROM SmokeTestSecurityScore__c
            WITH SECURITY_ENFORCED
            ORDER BY CheckedAt__c DESC NULLS LAST
            LIMIT 1
        ];
        return scores.isEmpty() ? null : scores[0];
    }

    private static Boolean hasAdminPermission() {
        Integer count = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND   PermissionSet.Name = 'SmokeTest_Admin'
            WITH SECURITY_ENFORCED
        ];
        return count > 0;
    }
}
