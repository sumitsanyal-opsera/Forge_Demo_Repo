/**
 * Anonymous Apex script to verify SmokeTestChecklist__mdt and SmokeTestAlertRoute__mdt records.
 * Run via: sf apex run --file scripts/verify-cmt-checklist-alertroute.apex --target-org <alias>
 *
 * Verifies:
 * - 5 SmokeTestChecklist__mdt records exist with correct CheckType, Severity, and ExecutionOrder
 * - 5 SmokeTestAlertRoute__mdt records exist with correct Channel and filter values
 * - WebhookSecret__c field exists on AlertRoute records (placeholder value, not a real secret)
 */

// --- Step 1: Verify SmokeTestChecklist__mdt records ---
Map<String, SmokeTestChecklist__mdt> checklistMap = SmokeTestChecklist__mdt.getAll();
System.debug('=== SmokeTestChecklist__mdt records (' + checklistMap.size() + ') ===');
System.assertEquals(5, checklistMap.size(), 'Should have exactly 5 checklist records');

// Expected: DeveloperName -> [CheckType, Severity, ExecutionOrder]
Map<String, String[]> expectedChecklist = new Map<String, String[]>{
    'Validate_Flows_Active'      => new String[]{'MetadataQuery', 'Critical', '1'},
    'Validate_Permission_Sets'   => new String[]{'SOQLValidation', 'Critical', '2'},
    'Validate_Page_Layouts'      => new String[]{'MetadataQuery',  'Warning',  '3'},
    'Validate_Custom_Settings'   => new String[]{'SOQLValidation', 'Warning',  '4'},
    'Validate_Scheduled_Jobs'    => new String[]{'SOQLValidation', 'Info',     '5'}
};

for (String key : checklistMap.keySet()) {
    SmokeTestChecklist__mdt item = checklistMap.get(key);
    System.debug(
        'DeveloperName=' + item.DeveloperName +
        ' | CheckType=' + item.CheckType__c +
        ' | Severity=' + item.Severity__c +
        ' | Order=' + item.ExecutionOrder__c +
        ' | Enabled=' + item.IsEnabled__c
    );
    System.assertEquals(true, item.IsEnabled__c, 'All default checklist items should be enabled: ' + item.DeveloperName);
    System.assertNotEquals(null, item.Query__c, 'Query__c must be populated: ' + item.DeveloperName);
    System.assertNotEquals(null, item.ExpectedResult__c, 'ExpectedResult__c must be populated: ' + item.DeveloperName);
    System.assertNotEquals(null, item.FailureMessage__c, 'FailureMessage__c must be populated: ' + item.DeveloperName);

    if (expectedChecklist.containsKey(item.DeveloperName)) {
        String[] exp = expectedChecklist.get(item.DeveloperName);
        System.assertEquals(exp[0], item.CheckType__c,
            'CheckType mismatch for ' + item.DeveloperName);
        System.assertEquals(exp[1], item.Severity__c,
            'Severity mismatch for ' + item.DeveloperName);
        System.assertEquals(Integer.valueOf(exp[2]), Integer.valueOf(item.ExecutionOrder__c),
            'ExecutionOrder mismatch for ' + item.DeveloperName);
    }
}
System.debug('SUCCESS: All 5 SmokeTestChecklist__mdt records verified.');

// --- Step 2: Verify SmokeTestAlertRoute__mdt records ---
Map<String, SmokeTestAlertRoute__mdt> routeMap = SmokeTestAlertRoute__mdt.getAll();
System.debug('=== SmokeTestAlertRoute__mdt records (' + routeMap.size() + ') ===');
System.assertEquals(5, routeMap.size(), 'Should have exactly 5 alert route records');

// Expected: DeveloperName -> [Channel, AlertOnFail, AlertOnPass, ScenarioFilter]
Map<String, String[]> expectedRoutes = new Map<String, String[]>{
    'TeamLead_AllFailures'      => new String[]{'Email', 'true',  'false', null},
    'BusinessOwner_Tagged'      => new String[]{'Email', 'true',  'false', 'Sales'},
    'QA_AllPlusFalsePositive'   => new String[]{'Email', 'true',  'true',  null},
    'Admin_SecurityAlerts'      => new String[]{'InApp', 'true',  'false', 'Security'},
    'DevOps_PipelineFailures'   => new String[]{'Slack', 'true',  'false', null}
};

for (String key : routeMap.keySet()) {
    SmokeTestAlertRoute__mdt route = routeMap.get(key);
    System.debug(
        'DeveloperName=' + route.DeveloperName +
        ' | Channel=' + route.Channel__c +
        ' | AlertOnFail=' + route.AlertOnFail__c +
        ' | AlertOnPass=' + route.AlertOnPass__c +
        ' | ScenarioFilter=' + route.ScenarioFilter__c +
        ' | IncludeDetails=' + route.IncludeDetails__c
    );

    if (expectedRoutes.containsKey(route.DeveloperName)) {
        String[] exp = expectedRoutes.get(route.DeveloperName);
        System.assertEquals(exp[0], route.Channel__c,
            'Channel mismatch for ' + route.DeveloperName);
        System.assertEquals(Boolean.valueOf(exp[1]), route.AlertOnFail__c,
            'AlertOnFail mismatch for ' + route.DeveloperName);
        System.assertEquals(Boolean.valueOf(exp[2]), route.AlertOnPass__c,
            'AlertOnPass mismatch for ' + route.DeveloperName);
        if (exp[3] != null) {
            System.assertEquals(exp[3], route.ScenarioFilter__c,
                'ScenarioFilter mismatch for ' + route.DeveloperName);
        }
    }
}

// Verify DevOps route has placeholder webhook values (not null)
SmokeTestAlertRoute__mdt devOpsRoute = routeMap.get('DevOps_PipelineFailures');
System.assertNotEquals(null, devOpsRoute.WebhookUrl__c, 'DevOps route must have a WebhookUrl placeholder');
System.assertNotEquals(null, devOpsRoute.WebhookSecret__c, 'DevOps route must have a WebhookSecret placeholder');
System.assertEquals('https://hooks.example.com/placeholder', devOpsRoute.WebhookUrl__c,
    'DevOps route WebhookUrl should contain placeholder value');
System.assertEquals('PLACEHOLDER_SECRET_REPLACE_IN_TARGET_ORG', devOpsRoute.WebhookSecret__c,
    'DevOps route WebhookSecret should contain placeholder value');

System.debug('SUCCESS: All 5 SmokeTestAlertRoute__mdt records verified.');
System.debug('=== CMT checklist and alert route verification PASSED ===');
