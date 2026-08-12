trigger SmokeTestAuditLogTrigger on SmokeTestAuditLog__c (before update, before delete) {
    if (Trigger.isBefore) {
        if (Trigger.isUpdate) {
            SmokeTestAuditLogTriggerHandler.handleBeforeUpdate(Trigger.new);
        } else if (Trigger.isDelete) {
            SmokeTestAuditLogTriggerHandler.handleBeforeDelete(Trigger.old);
        }
    }
}
