public without sharing class ChecklistEvaluator {

    @TestVisible
    private static ChecklistContext.IHttpCallout httpCalloutOverride;

    private final IDmlHandler dmlHandler;

    public ChecklistEvaluator() {
        this.dmlHandler = new DefaultDmlHandler();
    }

    @TestVisible
    ChecklistEvaluator(IDmlHandler dmlHandler) {
        this.dmlHandler = dmlHandler;
    }

    public List<ChecklistResult> evaluate(Id executionId) {
        List<ManifestComponent> components = loadManifestComponents(executionId);
        Map<String, SmokeTestChecklist__mdt> config = SmokeTestChecklist__mdt.getAll();

        ChecklistContext.IHttpCallout callout = httpCalloutOverride != null
            ? httpCalloutOverride : new DefaultHttpCallout();

        ChecklistContext ctx = new ChecklistContext(executionId, components, config, callout);

        List<IChecklistCheck> checks = new List<IChecklistCheck>{
            new FlowActivationCheck(),
            new PermissionSetAssignmentCheck(),
            new PageLayoutAssignmentCheck(),
            new ConfigValueCheck(),
            new ScheduledJobCheck()
        };

        List<ChecklistResult> results = new List<ChecklistResult>();
        for (IChecklistCheck check : checks) {
            try {
                results.add(check.execute(ctx));
            } catch (Exception e) {
                results.add(new ChecklistResult(
                    check.getClass().getName(), 'UNKNOWN',
                    ChecklistResult.Status.WARNING,
                    'Check executes without error',
                    'Unexpected error',
                    'Unexpected error in checklist check: ' + ErrorSanitizer.sanitize(e.getMessage())
                ));
            }
        }

        persistResults(executionId, results);
        return results;
    }

    private static List<ManifestComponent> loadManifestComponents(Id executionId) {
        if (executionId == null) return new List<ManifestComponent>();
        List<SmokeTestExecution__c> execs = [
            SELECT Id, DeploymentManifest__c
            FROM SmokeTestExecution__c
            WHERE Id = :executionId
            LIMIT 1
        ];
        if (execs.isEmpty() || String.isBlank(execs[0].DeploymentManifest__c)) {
            return new List<ManifestComponent>();
        }
        try {
            return DeploymentManifestParser.parse(execs[0].DeploymentManifest__c);
        } catch (Exception e) {
            return new List<ManifestComponent>();
        }
    }

    private void persistResults(Id executionId, List<ChecklistResult> results) {
        List<SmokeTestResult__c> records = new List<SmokeTestResult__c>();
        for (ChecklistResult r : results) {
            records.add(new SmokeTestResult__c(
                Execution__c    = executionId,
                ResultType__c   = 'CHECKLIST',
                ScenarioName__c = r.checkName,
                ScenarioType__c = r.checkType,
                Status__c       = toPicklistLabel(r.status),
                ExpectedState__c = r.expectedValue,
                ActualState__c  = r.actualValue,
                ErrorMessage__c = r.detail
            ));
        }
        if (!records.isEmpty()) {
            dmlHandler.insertRecords(records);
        }
    }

    private static String toPicklistLabel(ChecklistResult.Status s) {
        if (s == ChecklistResult.Status.PASS)    return 'Pass';
        if (s == ChecklistResult.Status.FAIL)    return 'Fail';
        if (s == ChecklistResult.Status.WARNING) return 'Warning';
        return 'Warning';
    }

    private class DefaultHttpCallout implements ChecklistContext.IHttpCallout {
        public HttpResponse send(HttpRequest req) {
            return new Http().send(req);
        }
    }

    private class DefaultDmlHandler implements IDmlHandler {
        public void insertRecord(SObject record) {
            insert record;
        }
        public void insertRecords(List<SObject> records) {
            insert records;
        }
    }
}
