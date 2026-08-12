/**
 * Anonymous Apex script to verify SmokeTestConfig__mdt and SmokeTestScenario__mdt records.
 * Run via: sf apex run --file scripts/verify-cmt-config.apex --target-org <alias>
 *
 * Verifies:
 * - Default SmokeTestConfig__mdt record exists with all expected field values
 * - Exactly 10 SmokeTestScenario__mdt records exist, all enabled, in order 1-10
 * - ScenarioClass__c values match expected class names
 */

// --- Step 1: Verify SmokeTestConfig__mdt.Default ---
Map<String, SmokeTestConfig__mdt> configMap = SmokeTestConfig__mdt.getAll();
System.assert(configMap.containsKey('Default'), 'Default SmokeTestConfig__mdt record must exist');

SmokeTestConfig__mdt cfg = configMap.get('Default');
System.debug('=== SmokeTestConfig__mdt.Default ===');
System.debug('MaxExecutionTimeMinutes: '    + cfg.MaxExecutionTimeMinutes__c);
System.debug('MaxConcurrentExecutions: '    + cfg.MaxConcurrentExecutions__c);
System.debug('CircuitBreakerThreshold: '    + cfg.CircuitBreakerThreshold__c);
System.debug('SecurityScoreAbsThreshold: '  + cfg.SecurityScoreAbsoluteThreshold__c);
System.debug('SecurityScoreRelThreshold: '  + cfg.SecurityScoreRelativeThreshold__c);
System.debug('DefaultRollbackPolicy: '      + cfg.DefaultRollbackPolicy__c);
System.debug('RollbackConfirmWindow: '      + cfg.RollbackConfirmationWindowSec__c);
System.debug('DataRetentionInternal: '      + cfg.DataRetentionDaysInternal__c);
System.debug('DataRetentionConfidential: '  + cfg.DataRetentionDaysConfidential__c);
System.debug('PerScenarioTimeout: '         + cfg.PerScenarioTimeoutSec__c);
System.debug('GovernorBudgetCPU: '          + cfg.GovernorBudgetCPUMs__c);
System.debug('GovernorBudgetSOQL: '         + cfg.GovernorBudgetSOQL__c);
System.debug('GovernorBudgetDML: '          + cfg.GovernorBudgetDML__c);
System.debug('BackpressureQueueDepth: '     + cfg.BackpressureQueueDepthPct__c);
System.debug('EnableWebhookCallbacks: '     + cfg.EnableWebhookCallbacks__c);

// Assert default values
System.assertEquals(5,    cfg.MaxExecutionTimeMinutes__c,       'MaxExecutionTimeMinutes should be 5');
System.assertEquals(50,   cfg.MaxConcurrentExecutions__c,       'MaxConcurrentExecutions should be 50');
System.assertEquals(3,    cfg.CircuitBreakerThreshold__c,       'CircuitBreakerThreshold should be 3');
System.assertEquals(80,   cfg.SecurityScoreAbsoluteThreshold__c,'SecurityScoreAbsoluteThreshold should be 80');
System.assertEquals(5,    cfg.SecurityScoreRelativeThreshold__c,'SecurityScoreRelativeThreshold should be 5');
System.assertEquals('Recommend Only', cfg.DefaultRollbackPolicy__c, 'DefaultRollbackPolicy should be Recommend Only');
System.assertEquals(60,   cfg.RollbackConfirmationWindowSec__c, 'RollbackConfirmationWindow should be 60');
System.assertEquals(90,   cfg.DataRetentionDaysInternal__c,     'DataRetentionInternal should be 90');
System.assertEquals(365,  cfg.DataRetentionDaysConfidential__c, 'DataRetentionConfidential should be 365');
System.assertEquals(30,   cfg.PerScenarioTimeoutSec__c,         'PerScenarioTimeout should be 30');
System.assertEquals(5000, cfg.GovernorBudgetCPUMs__c,           'GovernorBudgetCPU should be 5000');
System.assertEquals(50,   cfg.GovernorBudgetSOQL__c,            'GovernorBudgetSOQL should be 50');
System.assertEquals(50,   cfg.GovernorBudgetDML__c,             'GovernorBudgetDML should be 50');
System.assertEquals(80,   cfg.BackpressureQueueDepthPct__c,     'BackpressureQueueDepth should be 80');
System.assertEquals(true, cfg.EnableWebhookCallbacks__c,        'EnableWebhookCallbacks should be true');
System.debug('SUCCESS: SmokeTestConfig__mdt.Default field values verified.');

// --- Step 2: Verify SmokeTestScenario__mdt records ---
Map<String, SmokeTestScenario__mdt> scenarioMap = SmokeTestScenario__mdt.getAll();
System.debug('=== SmokeTestScenario__mdt records (' + scenarioMap.size() + ') ===');
System.assertEquals(10, scenarioMap.size(), 'Should have exactly 10 scenario records');

// Sort by execution order and output
List<SmokeTestScenario__mdt> scenarios = scenarioMap.values();
scenarios.sort();

// Expected scenario DeveloperNames and class names in order
Map<Integer, String[]> expected = new Map<Integer, String[]>{
    1  => new String[]{'Account_CRUD',         'AccountCrudScenario',           'true'},
    2  => new String[]{'Contact_CRUD',          'ContactCrudScenario',           'false'},
    3  => new String[]{'Opportunity_Pipeline',  'OpportunityCrudScenario',       'true'},
    4  => new String[]{'Case_Creation',         'CaseCreationScenario',          'false'},
    5  => new String[]{'Lead_Conversion',       'LeadConversionScenario',        'false'},
    6  => new String[]{'Flow_Execution',        'FlowExecutionScenario',         'false'},
    7  => new String[]{'Automation_Trigger',    'AutomationTriggerScenario',     'false'},
    8  => new String[]{'Report_Generation',     'ReportQueryScenario',           'false'},
    9  => new String[]{'PageLayout_Render',     'PageLayoutRenderScenario',      'false'},
    10 => new String[]{'Integration_Callout',   'IntegrationConnectivityScenario','false'}
};

for (SmokeTestScenario__mdt scen : scenarios) {
    System.debug(
        'Order=' + scen.ExecutionOrder__c +
        ' | DeveloperName=' + scen.DeveloperName +
        ' | Class=' + scen.ScenarioClass__c +
        ' | Enabled=' + scen.IsEnabled__c +
        ' | Critical=' + scen.IsCritical__c +
        ' | BusinessProcess=' + scen.BusinessProcess__c
    );
    System.assertEquals(true, scen.IsEnabled__c, 'All default scenarios should be enabled: ' + scen.DeveloperName);

    Integer order = Integer.valueOf(scen.ExecutionOrder__c);
    if (expected.containsKey(order)) {
        String[] exp = expected.get(order);
        System.assertEquals(exp[0], scen.DeveloperName,    'DeveloperName mismatch at order ' + order);
        System.assertEquals(exp[1], scen.ScenarioClass__c, 'ScenarioClass mismatch at order ' + order);
        System.assertEquals(exp[2], String.valueOf(scen.IsCritical__c), 'IsCritical mismatch at order ' + order);
    }
}

System.debug('SUCCESS: All 10 SmokeTestScenario__mdt records verified.');
System.debug('=== CMT configuration verification PASSED ===');
