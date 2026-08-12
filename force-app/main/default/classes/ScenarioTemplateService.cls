/**
 * Provides static template definitions for the Guided Setup Wizard and handles
 * bulk deployment of selected templates as SmokeTestScenario__mdt records.
 *
 * Templates are product-defined constants (not user-configurable CMT) so they
 * live as Apex static data.
 */
public with sharing class ScenarioTemplateService {

    // =========================================================================
    // Inner classes
    // =========================================================================

    public class ScenarioTemplate {
        @AuraEnabled public String  scenarioName;
        @AuraEnabled public String  apexClassName;
        @AuraEnabled public Integer executionOrder;
        @AuraEnabled public Integer timeout;
        @AuraEnabled public Integer cpuBudget;
        @AuraEnabled public Integer soqlBudget;
        @AuraEnabled public Integer dmlBudget;
        @AuraEnabled public String  cloudType;
        @AuraEnabled public Boolean critical;
        @AuraEnabled public String  description;
        @AuraEnabled public String  label;

        public ScenarioTemplate(
            String scenarioName, String label, String apexClassName,
            Integer executionOrder, Integer timeout,
            Integer cpuBudget, Integer soqlBudget, Integer dmlBudget,
            String cloudType, Boolean critical, String description
        ) {
            this.scenarioName   = scenarioName;
            this.label          = label;
            this.apexClassName  = apexClassName;
            this.executionOrder = executionOrder;
            this.timeout        = timeout;
            this.cpuBudget      = cpuBudget;
            this.soqlBudget     = soqlBudget;
            this.dmlBudget      = dmlBudget;
            this.cloudType      = cloudType;
            this.critical       = critical;
            this.description    = description;
        }
    }

    public class DeployTemplatesResult {
        @AuraEnabled public Boolean       success;
        @AuraEnabled public String        jobId;
        @AuraEnabled public Integer       deployedCount;
        @AuraEnabled public List<String>  skippedNames;
        @AuraEnabled public List<String>  warningClassNames;
        @AuraEnabled public String        errorMessage;

        public DeployTemplatesResult() {
            this.skippedNames      = new List<String>();
            this.warningClassNames = new List<String>();
            this.deployedCount     = 0;
        }
    }

    // =========================================================================
    // Template definitions
    // =========================================================================

    @AuraEnabled(cacheable=true)
    public static List<ScenarioTemplate> getSalesCloudTemplates() {
        return new List<ScenarioTemplate>{
            new ScenarioTemplate(
                'Account_CRUD', 'Account CRUD', 'AccountCrudScenario',
                10, 30, 2000, 25, 10, 'Sales', true,
                'Verifies Account create, read, update, and delete operations'
            ),
            new ScenarioTemplate(
                'Contact_CRUD', 'Contact CRUD', 'ContactCrudScenario',
                20, 30, 2000, 25, 10, 'Sales', true,
                'Verifies Contact create, read, update, and delete with parent Account'
            ),
            new ScenarioTemplate(
                'Opportunity_Pipeline', 'Opportunity Pipeline', 'OpportunityCrudScenario',
                30, 45, 3000, 30, 15, 'Sales', true,
                'Verifies Opportunity pipeline stage progression through Closed Won'
            ),
            new ScenarioTemplate(
                'Lead_Conversion', 'Lead Conversion', 'LeadConversionScenario',
                40, 45, 3000, 30, 15, 'Sales', true,
                'Verifies Lead qualification and conversion to Account, Contact, Opportunity'
            )
        };
    }

    @AuraEnabled(cacheable=true)
    public static List<ScenarioTemplate> getServiceCloudTemplates() {
        return new List<ScenarioTemplate>{
            new ScenarioTemplate(
                'Case_Creation', 'Case Creation', 'CaseCreationScenario',
                50, 30, 2000, 25, 10, 'Service', true,
                'Verifies Case creation with assignment rules and status tracking'
            ),
            new ScenarioTemplate(
                'Flow_Execution', 'Flow Execution', 'FlowExecutionScenario',
                60, 45, 5000, 50, 20, 'Service', false,
                'Verifies active Screen and Record-Triggered Flows execute without errors'
            ),
            new ScenarioTemplate(
                'Automation_Trigger', 'Automation Trigger', 'AutomationTriggerScenario',
                70, 30, 2000, 25, 15, 'Service', false,
                'Verifies Apex triggers fire correctly and automation logic executes'
            )
        };
    }

    @AuraEnabled(cacheable=true)
    public static List<ScenarioTemplate> getExperienceCloudTemplates() {
        return new List<ScenarioTemplate>{
            new ScenarioTemplate(
                'Integration_Callout', 'Integration Connectivity', 'IntegrationConnectivityScenario',
                80, 45, 3000, 20, 5, 'Experience', false,
                'Verifies outbound integration callouts and connected app connectivity'
            ),
            new ScenarioTemplate(
                'Report_Generation', 'Report Generation', 'ReportQueryScenario',
                90, 60, 5000, 100, 5, 'Experience', false,
                'Verifies report and dashboard queries return results within time limits'
            )
        };
    }

    // =========================================================================
    // Apex class validation
    // =========================================================================

    @AuraEnabled(cacheable=true)
    public static Map<String, Boolean> validateApexClasses(List<String> classNames) {
        Map<String, Boolean> result = new Map<String, Boolean>();
        if (classNames == null) return result;
        for (String className : classNames) {
            result.put(className, Type.forName(className) != null);
        }
        return result;
    }

    // =========================================================================
    // Bulk deployment
    // =========================================================================

    @AuraEnabled
    public static DeployTemplatesResult bulkDeployTemplates(
        List<Map<String, Object>> scenarios
    ) {
        DeployTemplatesResult result = new DeployTemplatesResult();

        if (scenarios == null || scenarios.isEmpty()) {
            result.success      = false;
            result.errorMessage = 'No scenarios provided for deployment';
            return result;
        }

        // Validate Apex class existence and warn about missing ones
        for (Map<String, Object> scenario : scenarios) {
            String className = String.valueOf(scenario.get('apexClassName'));
            if (String.isNotBlank(className) && Type.forName(className) == null) {
                result.warningClassNames.add(className);
            }
        }

        // De-duplicate against existing CMT records
        Set<String> existingNames = new Set<String>();
        for (SmokeTestScenario__mdt existing : SmokeTestScenario__mdt.getAll().values()) {
            existingNames.add(existing.DeveloperName);
        }

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        List<String> deployedLabels = new List<String>();

        for (Map<String, Object> scenario : scenarios) {
            String developerName = String.valueOf(scenario.get('scenarioName'));
            String label         = String.valueOf(scenario.get('label'));

            if (existingNames.contains(developerName)) {
                result.skippedNames.add(developerName);
                continue;
            }

            Metadata.CustomMetadata record = buildCmtRecord(developerName, label, scenario);
            container.addMetadata(record);
            deployedLabels.add(label);
            result.deployedCount++;
        }

        if (result.deployedCount == 0) {
            result.success = true;
            result.jobId   = null;
            return result;
        }

        MetadataDeployService.DeployResult deploy = MetadataDeployService.deployBulk(container);
        result.success      = deploy.success;
        result.jobId        = deploy.jobId;
        result.errorMessage = deploy.success ? null : deploy.errorMessage;

        if (deploy.success) {
            writeAuditLog(deployedLabels, result.warningClassNames);
        }

        return result;
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private static Metadata.CustomMetadata buildCmtRecord(
        String developerName,
        String label,
        Map<String, Object> scenario
    ) {
        Metadata.CustomMetadata record = new Metadata.CustomMetadata();
        record.fullName = 'SmokeTestScenario.' + developerName;
        record.label    = String.isBlank(label) ? developerName : label;

        addField(record, 'ScenarioClass__c',            scenario.get('apexClassName'));
        addField(record, 'IsEnabled__c',                true);
        addField(record, 'IsCritical__c',               scenario.get('critical'));
        addField(record, 'BusinessProcess__c',          scenario.get('cloudType'));
        addField(record, 'Description__c',              scenario.get('description'));
        addField(record, 'ExecutionOrder__c',           scenario.get('executionOrder'));
        addField(record, 'TimeoutOverrideSec__c',       scenario.get('timeout'));
        addField(record, 'GovernorBudgetOverrideCPU__c', scenario.get('cpuBudget'));
        addField(record, 'GovernorBudgetOverrideSOQL__c', scenario.get('soqlBudget'));
        addField(record, 'GovernorBudgetOverrideDML__c', scenario.get('dmlBudget'));

        return record;
    }

    private static void addField(
        Metadata.CustomMetadata record,
        String fieldName,
        Object value
    ) {
        if (value == null) return;
        Metadata.CustomMetadataValue cv = new Metadata.CustomMetadataValue();
        cv.field = fieldName;
        cv.value = value;
        record.values.add(cv);
    }

    private static void writeAuditLog(List<String> deployed, List<String> warnings) {
        List<String> cloudNames = new List<String>();
        // Extract unique cloud types from deployed names
        for (String name : deployed) {
            cloudNames.add(name);
        }
        String reason = 'Initial setup via Guided Wizard - '
            + String.join(deployed, ', ');

        AuditLogEntry entry = new AuditLogEntry.Builder()
            .actorUserId(UserInfo.getUserId())
            .actionType(AuditLogEntry.ACTION_CONFIG_CHANGE)
            .resourceType('SmokeTestScenario__mdt')
            .newValue('Deployed: ' + String.join(deployed, ', ')
                + (warnings.isEmpty() ? '' : '; Warnings: ' + String.join(warnings, ', ')))
            .changeReason(reason)
            .outcome('SUCCESS')
            .build();
        new AuditLogWriter(new DefaultDmlHandler()).logAction(entry);
    }
}
