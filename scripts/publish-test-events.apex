/**
 * Anonymous Apex script to publish test instances of all three smoke test Platform Events.
 * Run via: sf apex run --file scripts/publish-test-events.apex --target-org <alias>
 *
 * Event architecture:
 *   DeploymentComplete__e  — Publisher: deployment tooling (Copado, Gearset, sf CLI)
 *                            Subscriber: SmokeTestOrchestratorTrigger (trigger on __e)
 *
 *   SmokeTestProgress__e   — Publisher: SmokeTestOrchestrator (Queueable Apex)
 *                            Subscriber: SmokeTestDashboard LWC via lightning/empApi
 *
 *   SmokeTestComplete__e   — Publisher: SmokeTestOrchestrator (Queueable Apex)
 *                            Subscribers: AlertRoutingService, WebhookCallbackHandler,
 *                                         SmokeTestDashboard LWC
 *
 * NOTE: EventBus.publish() has a governor limit of 150 publish calls per transaction.
 * The orchestrator must batch publish calls when producing many progress events.
 * If no subscribers are registered, events publish successfully but are not consumed —
 * this is expected during initial setup before triggers and LWC components are deployed.
 */

// --- Publish DeploymentComplete__e ---
DeploymentComplete__e deployEvt = new DeploymentComplete__e(
    DeploymentId__c       = '0Af000000000001AAA',
    TargetOrg__c          = '00D000000000001AAA',
    DeployedBy__c         = 'deploy-bot@mycompany.com',
    DeploymentStatus__c   = 'Succeeded',
    Timestamp__c          = DateTime.now()
);

Database.SaveResult deployResult = EventBus.publish(deployEvt);
if (deployResult.isSuccess()) {
    System.debug('SUCCESS: DeploymentComplete__e published');
} else {
    for (Database.Error err : deployResult.getErrors()) {
        System.debug('ERROR publishing DeploymentComplete__e: ' + err.getMessage());
    }
}
System.assert(deployResult.isSuccess(), 'DeploymentComplete__e publish should succeed');

// --- Publish SmokeTestProgress__e ---
SmokeTestProgress__e progressEvt = new SmokeTestProgress__e(
    ExecutionId__c    = 'a00000000000001AAA',
    ScenarioName__c   = 'Account_CRUD',
    ScenarioStatus__c = 'Passed',
    CompletedCount__c = 3,
    TotalCount__c     = 10,
    CurrentPhase__c   = 'Running Scenarios'
);

Database.SaveResult progressResult = EventBus.publish(progressEvt);
if (progressResult.isSuccess()) {
    System.debug('SUCCESS: SmokeTestProgress__e published');
} else {
    for (Database.Error err : progressResult.getErrors()) {
        System.debug('ERROR publishing SmokeTestProgress__e: ' + err.getMessage());
    }
}
System.assert(progressResult.isSuccess(), 'SmokeTestProgress__e publish should succeed');

// --- Publish SmokeTestComplete__e ---
SmokeTestComplete__e completeEvt = new SmokeTestComplete__e(
    ExecutionId__c        = 'a00000000000001AAA',
    OverallResult__c      = 'Passed',
    PassedCount__c        = 9,
    FailedCount__c        = 1,
    ExecutionTimeMs__c    = 47832,
    SecurityScoreMet__c   = true,
    RollbackRecommended__c = false
);

Database.SaveResult completeResult = EventBus.publish(completeEvt);
if (completeResult.isSuccess()) {
    System.debug('SUCCESS: SmokeTestComplete__e published');
} else {
    for (Database.Error err : completeResult.getErrors()) {
        System.debug('ERROR publishing SmokeTestComplete__e: ' + err.getMessage());
    }
}
System.assert(completeResult.isSuccess(), 'SmokeTestComplete__e publish should succeed');

System.debug('=== All 3 Platform Events published successfully ===');
System.debug('Events are HighVolume with PublishImmediately behavior.');
System.debug('Use Developer Console > Event Log or Event Monitoring to confirm delivery.');
