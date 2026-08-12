trigger DeploymentCompleteTrigger on DeploymentComplete__e (after insert) {
    DeploymentCompleteTriggerHandler.handleEvents(Trigger.new);
}
