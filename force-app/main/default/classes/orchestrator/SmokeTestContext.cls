global with sharing class SmokeTestContext {

    global final Id                  executionId;
    global final String              targetOrg;
    global final Map<String, Object> parameters;

    global SmokeTestContext(
        Id                  executionId,
        String              targetOrg,
        Map<String, Object> parameters
    ) {
        if (executionId == null) {
            throw new IllegalArgumentException('executionId must not be null');
        }
        this.executionId = executionId;
        this.targetOrg   = targetOrg;
        this.parameters  = (parameters != null) ? parameters : new Map<String, Object>();
    }
}
