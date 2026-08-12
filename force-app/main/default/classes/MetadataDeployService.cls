/**
 * Shared service wrapping Metadata.Operations.enqueueDeployment() for Custom Metadata
 * Type writes. Standard DML is prohibited on CMT records; this service queues an async
 * Metadata API deployment and implements DeployCallback for status tracking.
 */
public with sharing class MetadataDeployService implements Metadata.DeployCallback {

    public class MetadataDeployException extends Exception {}

    public class DeployResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  jobId;
        @AuraEnabled public String  errorMessage;

        public DeployResult(Boolean success, String jobId, String errorMessage) {
            this.success      = success;
            this.jobId        = jobId;
            this.errorMessage = errorMessage;
        }
    }

    // Bypasses the actual enqueueDeployment() call in @isTest context
    @TestVisible static Boolean bypassDeployment = false;
    // Exposes the last built container for test assertions
    @TestVisible static Metadata.DeployContainer lastContainer;

    // Metadata.DeployCallback implementation
    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        if (!result.success) {
            System.debug(LoggingLevel.ERROR,
                'MetadataDeployService: deployment failed — ' + result.errorMessage);
        }
    }

    /**
     * Deploys a pre-built Metadata.DeployContainer (used for bulk operations).
     *
     * @param container Pre-built container with one or more CMT records
     * @return          DeployResult with success flag and async jobId
     */
    public static DeployResult deployBulk(Metadata.DeployContainer container) {
        try {
            lastContainer = container;

            if (bypassDeployment) {
                return new DeployResult(true, 'TEST_JOB_ID', null);
            }

            MetadataDeployService callback = new MetadataDeployService();
            Id jobId = Metadata.Operations.enqueueDeployment(container, callback);
            return new DeployResult(true, String.valueOf(jobId), null);

        } catch (Exception ex) {
            return new DeployResult(false, null, ex.getMessage());
        }
    }

    /**
     * Upserts a single Custom Metadata Type record via the Metadata API.
     *
     * @param mdtApiName    Object API name, e.g. 'SmokeTestScenario__mdt'
     * @param developerName DeveloperName of the record, e.g. 'Account_CRUD'
     * @param label         Human-readable label
     * @param fieldValues   Map of field API names to values
     * @return              DeployResult with success flag and async jobId
     */
    public static DeployResult upsertCustomMetadata(
        String mdtApiName,
        String developerName,
        String label,
        Map<String, Object> fieldValues
    ) {
        try {
            Metadata.CustomMetadata record = new Metadata.CustomMetadata();
            String typeName = mdtApiName.endsWith('__mdt')
                ? mdtApiName.removeEnd('__mdt')
                : mdtApiName;
            record.fullName = typeName + '.' + developerName;
            record.label    = label;

            if (fieldValues != null) {
                for (String fieldName : fieldValues.keySet()) {
                    Metadata.CustomMetadataValue cv = new Metadata.CustomMetadataValue();
                    cv.field = fieldName;
                    cv.value = fieldValues.get(fieldName);
                    record.values.add(cv);
                }
            }

            Metadata.DeployContainer container = new Metadata.DeployContainer();
            container.addMetadata(record);
            lastContainer = container;

            if (bypassDeployment) {
                return new DeployResult(true, 'TEST_JOB_ID', null);
            }

            MetadataDeployService callback = new MetadataDeployService();
            Id jobId = Metadata.Operations.enqueueDeployment(container, callback);
            return new DeployResult(true, String.valueOf(jobId), null);

        } catch (Exception ex) {
            return new DeployResult(false, null, ex.getMessage());
        }
    }
}
