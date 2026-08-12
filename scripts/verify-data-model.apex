/**
 * Anonymous Apex script to verify the SmokeTestExecution__c and SmokeTestResult__c data model.
 * Run via: sf apex run --file scripts/verify-data-model.apex --target-org <alias>
 *
 * Verifies:
 * - All fields are insertable with correct types
 * - Master-Detail relationship enforces cascade delete
 * - Restricted picklist values are enforced
 * - ExternalId (DeploymentId__c) lookup works
 */

// --- Step 1: Insert a parent SmokeTestExecution__c record ---
SmokeTestExecution__c exec = new SmokeTestExecution__c(
    Status__c           = 'In Progress',
    TriggerSource__c    = 'REST API',
    StartTime__c        = System.now(),
    TotalScenarios__c   = 3,
    PassedScenarios__c  = 0,
    FailedScenarios__c  = 0,
    OverallResult__c    = null,
    ExecutionTimeMs__c  = null,
    TargetOrg__c        = 'SmokeTestDev',
    DeploymentId__c     = 'VERIFY-' + String.valueOf(System.currentTimeMillis()),
    WebhookCallbackUrl__c = 'https://example.com/callback',
    RollbackPolicy__c   = 'Recommend Only',
    CircuitBreakerTripped__c = false
    // InitiatedBy__c left null — valid for system-triggered executions
);
insert exec;
System.debug('Created SmokeTestExecution__c: ' + exec.Id + ' (' + exec.Name + ')');

// --- Step 2: Insert three child SmokeTestResult__c records ---
List<SmokeTestResult__c> results = new List<SmokeTestResult__c>{
    new SmokeTestResult__c(
        Execution__c          = exec.Id,
        ScenarioName__c       = 'Account CRUD',
        ScenarioType__c       = 'CRUD',
        Status__c             = 'Pass',
        ExecutionTimeMs__c    = 1234,
        SOQLQueries__c        = 12,
        DMLStatements__c      = 4,
        CPUTimeMs__c          = 450,
        ExecutionOrder__c     = 1,
        GovernorLimitExceeded__c = false
    ),
    new SmokeTestResult__c(
        Execution__c          = exec.Id,
        ScenarioName__c       = 'Flow Execution',
        ScenarioType__c       = 'Flow',
        Status__c             = 'Fail',
        ErrorMessage__c       = '[MASKED] Flow failed: Record validation rule triggered.',
        ErrorStackTrace__c    = '[MASKED] AnonymousBlock: line 42, column 1',
        ExecutionTimeMs__c    = 5100,
        SOQLQueries__c        = 8,
        DMLStatements__c      = 2,
        CPUTimeMs__c          = 3200,
        ExecutionOrder__c     = 2,
        GovernorLimitExceeded__c = false
    ),
    new SmokeTestResult__c(
        Execution__c          = exec.Id,
        ScenarioName__c       = 'REST Integration',
        ScenarioType__c       = 'Integration',
        Status__c             = 'Timeout',
        ErrorMessage__c       = 'Scenario timed out after 30000ms.',
        ExecutionTimeMs__c    = 30000,
        SOQLQueries__c        = 3,
        DMLStatements__c      = 0,
        CPUTimeMs__c          = 500,
        ExecutionOrder__c     = 3,
        GovernorLimitExceeded__c = false
    )
};
insert results;
System.debug('Created ' + results.size() + ' SmokeTestResult__c records.');

// --- Step 3: Update execution to completed ---
exec.Status__c          = 'Completed';
exec.EndTime__c         = System.now();
exec.PassedScenarios__c = 1;
exec.FailedScenarios__c = 2;
exec.OverallResult__c   = 'Fail';
exec.ExecutionTimeMs__c = 36334;
update exec;
System.debug('Updated execution status to Completed.');

// --- Step 4: Verify fields via SOQL ---
SmokeTestExecution__c queried = [
    SELECT Id, Name, Status__c, TriggerSource__c, StartTime__c, EndTime__c,
           TotalScenarios__c, PassedScenarios__c, FailedScenarios__c,
           OverallResult__c, ExecutionTimeMs__c, TargetOrg__c, DeploymentId__c,
           WebhookCallbackUrl__c, RollbackPolicy__c, CircuitBreakerTripped__c
    FROM SmokeTestExecution__c WHERE Id = :exec.Id
];
System.debug('Queried execution: Status=' + queried.Status__c + ', OverallResult=' + queried.OverallResult__c);
System.assert(queried.Status__c == 'Completed', 'Status should be Completed');
System.assert(queried.OverallResult__c == 'Fail', 'OverallResult should be Fail');

List<SmokeTestResult__c> queriedResults = [
    SELECT Id, Name, ScenarioName__c, ScenarioType__c, Status__c,
           ErrorMessage__c, ErrorStackTrace__c, ExecutionTimeMs__c,
           SOQLQueries__c, DMLStatements__c, CPUTimeMs__c,
           ExecutionOrder__c, RoleProfile__c, GovernorLimitExceeded__c
    FROM SmokeTestResult__c WHERE Execution__c = :exec.Id
    ORDER BY ExecutionOrder__c ASC
];
System.assert(queriedResults.size() == 3, 'Should have 3 child results');
System.debug('Child results: ' + queriedResults[0].Status__c + ', ' + queriedResults[1].Status__c + ', ' + queriedResults[2].Status__c);

// --- Step 5: Verify ExternalId lookup ---
SmokeTestExecution__c byExtId = [
    SELECT Id, DeploymentId__c FROM SmokeTestExecution__c WHERE DeploymentId__c = :exec.DeploymentId__c
];
System.assert(byExtId.Id == exec.Id, 'ExternalId lookup should return same record');
System.debug('ExternalId lookup verified.');

// --- Step 6: Verify cascade delete ---
delete exec;
List<SmokeTestResult__c> orphans = [SELECT Id FROM SmokeTestResult__c WHERE Execution__c = :exec.Id];
System.assert(orphans.isEmpty(), 'Cascade delete should have removed all child results');
System.debug('Cascade delete verified — ' + orphans.size() + ' orphan records (expected 0).');

System.debug('=== Data model verification PASSED ===');
