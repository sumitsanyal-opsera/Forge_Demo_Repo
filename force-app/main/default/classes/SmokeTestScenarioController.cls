/**
 * AuraEnabled Apex controller for the TestScenariosPage LWC.
 * Reads SmokeTestScenario__mdt records and writes changes via MetadataDeployService.
 * All configuration changes are audit-logged via AuditLogWriter.
 *
 * Write operations are async (Metadata API) — the UI polls using the returned jobId.
 */
public with sharing class SmokeTestScenarioController {

    private static final Pattern DEVELOPER_NAME_PATTERN =
        Pattern.compile('^[a-zA-Z][a-zA-Z0-9_]{0,39}$');
    private static final Pattern APEX_CLASS_NAME_PATTERN =
        Pattern.compile('^[a-zA-Z][a-zA-Z0-9_]{0,255}$');

    private static final Integer TIMEOUT_MIN  = 1;
    private static final Integer TIMEOUT_MAX  = 60;
    private static final Integer CPU_MIN      = 1;
    private static final Integer CPU_MAX      = 10000;
    private static final Integer SOQL_MIN     = 1;
    private static final Integer SOQL_MAX     = 200;
    private static final Integer DML_MIN      = 1;
    private static final Integer DML_MAX      = 150;

    // =========================================================================
    // Read
    // =========================================================================

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getScenarios() {
        try {
            checkAdminPermission();
            List<SmokeTestScenario__mdt> all =
                new List<SmokeTestScenario__mdt>(SmokeTestScenario__mdt.getAll().values());
            all.sort(new ExecutionOrderComparator());
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            for (SmokeTestScenario__mdt s : all) {
                result.add(toMap(s));
            }
            return result;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            throw auraException(ex.getMessage());
        }
    }

    // =========================================================================
    // Toggle enable / disable
    // =========================================================================

    @AuraEnabled
    public static Map<String, Object> toggleScenario(
        String developerName,
        Boolean enabled,
        String changeReason
    ) {
        try {
            checkAdminPermission();
            if (String.isBlank(developerName)) throw auraException('developerName is required');
            if (enabled == null)               throw auraException('enabled is required');
            if (String.isBlank(changeReason))  throw auraException('changeReason is required');

            SmokeTestScenario__mdt scenario = SmokeTestScenario__mdt.getInstance(developerName);
            if (scenario == null) {
                throw auraException('Scenario not found: ' + developerName);
            }

            String oldVal = 'IsEnabled__c: ' + scenario.IsEnabled__c;
            String newVal = 'IsEnabled__c: ' + enabled;

            MetadataDeployService.DeployResult deploy = MetadataDeployService.upsertCustomMetadata(
                'SmokeTestScenario__mdt',
                developerName,
                scenario.MasterLabel,
                new Map<String, Object>{ 'IsEnabled__c' => enabled }
            );

            if (!deploy.success) throw auraException('Deployment failed: ' + deploy.errorMessage);

            writeAuditLog(developerName, oldVal, newVal, changeReason,
                deploy.success ? 'SUCCESS' : 'FAILURE');

            return new Map<String, Object>{
                'success' => true,
                'jobId'   => deploy.jobId
            };
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            throw auraException(ex.getMessage());
        }
    }

    // =========================================================================
    // Create scenario
    // =========================================================================

    @AuraEnabled
    public static Map<String, Object> createScenario(Map<String, Object> params) {
        try {
            checkAdminPermission();
            validateParams(params, true);

            String developerName = (String) params.get('developerName');
            String label         = String.isBlank((String) params.get('label'))
                ? developerName
                : (String) params.get('label');
            String changeReason  = (String) params.get('changeReason');

            Map<String, Object> fieldValues = buildFieldValues(params);

            MetadataDeployService.DeployResult deploy = MetadataDeployService.upsertCustomMetadata(
                'SmokeTestScenario__mdt',
                developerName,
                label,
                fieldValues
            );

            if (!deploy.success) throw auraException('Deployment failed: ' + deploy.errorMessage);

            writeAuditLog(developerName, null, JSON.serialize(fieldValues),
                changeReason, 'SUCCESS');

            return new Map<String, Object>{
                'success' => true,
                'jobId'   => deploy.jobId
            };
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            throw auraException(ex.getMessage());
        }
    }

    // =========================================================================
    // Update scenario
    // =========================================================================

    @AuraEnabled
    public static Map<String, Object> updateScenario(
        String developerName,
        Map<String, Object> params
    ) {
        try {
            checkAdminPermission();
            if (String.isBlank(developerName)) throw auraException('developerName is required');
            validateParams(params, false);

            SmokeTestScenario__mdt scenario = SmokeTestScenario__mdt.getInstance(developerName);
            if (scenario == null) {
                throw auraException('Scenario not found: ' + developerName);
            }

            String changeReason = (String) params.get('changeReason');
            if (String.isBlank(changeReason)) throw auraException('changeReason is required');

            Map<String, Object> fieldValues = buildFieldValues(params);
            String oldVal = JSON.serialize(toMap(scenario));

            MetadataDeployService.DeployResult deploy = MetadataDeployService.upsertCustomMetadata(
                'SmokeTestScenario__mdt',
                developerName,
                scenario.MasterLabel,
                fieldValues
            );

            if (!deploy.success) throw auraException('Deployment failed: ' + deploy.errorMessage);

            writeAuditLog(developerName, oldVal, JSON.serialize(fieldValues),
                changeReason, 'SUCCESS');

            return new Map<String, Object>{
                'success' => true,
                'jobId'   => deploy.jobId
            };
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            throw auraException(ex.getMessage());
        }
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private static void checkAdminPermission() {
        Integer count = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSet.Name = 'SmokeTest_Admin'
        ];
        if (count == 0) {
            throw auraException(
                'You must have the SmokeTest_Admin permission set to manage scenarios.');
        }
    }

    private static void validateParams(Map<String, Object> params, Boolean requireDeveloperName) {
        if (params == null) throw auraException('params must not be null');

        if (requireDeveloperName) {
            String devName = (String) params.get('developerName');
            if (String.isBlank(devName)) {
                throw auraException('Scenario name (developerName) is required');
            }
            if (!DEVELOPER_NAME_PATTERN.matcher(devName).matches()) {
                throw auraException(
                    'Scenario name must start with a letter and contain only letters, digits, ' +
                    'and underscores (max 40 characters). Got: ' + devName);
            }
        }

        // Apex class name validation
        String apexClass = (String) params.get('scenarioClass');
        if (!String.isBlank(apexClass)) {
            if (!APEX_CLASS_NAME_PATTERN.matcher(apexClass).matches()) {
                throw auraException('Apex class name is invalid: ' + apexClass);
            }
            // Verify the class implements ISmokeTestScenario
            Type t = Type.forName(apexClass);
            if (t == null) {
                throw auraException('Apex class not found: ' + apexClass);
            }
            Object instance;
            try {
                instance = t.newInstance();
            } catch (Exception ex) {
                throw auraException('Apex class cannot be instantiated: ' + apexClass);
            }
            if (!(instance instanceof ISmokeTestScenario)) {
                throw auraException(
                    'Apex class ' + apexClass + ' does not implement ISmokeTestScenario');
            }
        }

        // Numeric range validations
        validateIntRange(params, 'timeoutSec',  TIMEOUT_MIN, TIMEOUT_MAX,  'Timeout (seconds)');
        validateIntRange(params, 'cpuBudget',   CPU_MIN,     CPU_MAX,      'CPU budget (ms)');
        validateIntRange(params, 'soqlBudget',  SOQL_MIN,    SOQL_MAX,     'SOQL budget');
        validateIntRange(params, 'dmlBudget',   DML_MIN,     DML_MAX,      'DML budget');
    }

    private static void validateIntRange(
        Map<String, Object> params,
        String key,
        Integer minVal,
        Integer maxVal,
        String label
    ) {
        Object raw = params.get(key);
        if (raw == null) return;
        Integer val;
        try {
            val = Integer.valueOf(String.valueOf(raw));
        } catch (Exception ex) {
            throw auraException(label + ' must be a whole number');
        }
        if (val < minVal || val > maxVal) {
            throw auraException(label + ' must be between ' + minVal + ' and ' + maxVal +
                '. Got: ' + val);
        }
    }

    private static Map<String, Object> buildFieldValues(Map<String, Object> params) {
        Map<String, Object> fields = new Map<String, Object>();

        Object isEnabled = params.get('isEnabled');
        if (isEnabled != null) fields.put('IsEnabled__c', Boolean.valueOf(String.valueOf(isEnabled)));

        Object execOrder = params.get('executionOrder');
        if (execOrder != null) fields.put('ExecutionOrder__c', Decimal.valueOf(String.valueOf(execOrder)));

        Object scenClass = params.get('scenarioClass');
        if (!String.isBlank((String) scenClass)) fields.put('ScenarioClass__c', (String) scenClass);

        Object isCrit = params.get('isCritical');
        if (isCrit != null) fields.put('IsCritical__c', Boolean.valueOf(String.valueOf(isCrit)));

        Object bizProc = params.get('businessProcess');
        if (!String.isBlank((String) bizProc)) fields.put('BusinessProcess__c', (String) bizProc);

        Object desc = params.get('description');
        if (!String.isBlank((String) desc)) fields.put('Description__c', (String) desc);

        Object timeout = params.get('timeoutSec');
        if (timeout != null) fields.put('TimeoutOverrideSec__c', Decimal.valueOf(String.valueOf(timeout)));

        Object role = params.get('roleProfile');
        if (!String.isBlank((String) role)) fields.put('RoleProfile__c', (String) role);

        Object cpu = params.get('cpuBudget');
        if (cpu != null) fields.put('GovernorBudgetOverrideCPU__c', Decimal.valueOf(String.valueOf(cpu)));

        Object soql = params.get('soqlBudget');
        if (soql != null) fields.put('GovernorBudgetOverrideSOQL__c', Decimal.valueOf(String.valueOf(soql)));

        Object dml = params.get('dmlBudget');
        if (dml != null) fields.put('GovernorBudgetOverrideDML__c', Decimal.valueOf(String.valueOf(dml)));

        return fields;
    }

    private static Map<String, Object> toMap(SmokeTestScenario__mdt s) {
        return new Map<String, Object>{
            'developerName'  => s.DeveloperName,
            'label'          => s.MasterLabel,
            'isEnabled'      => s.IsEnabled__c,
            'executionOrder' => s.ExecutionOrder__c,
            'scenarioClass'  => s.ScenarioClass__c,
            'isCritical'     => s.IsCritical__c,
            'businessProcess'=> s.BusinessProcess__c,
            'description'    => s.Description__c,
            'timeoutSec'     => s.TimeoutOverrideSec__c,
            'roleProfile'    => s.RoleProfile__c,
            'cpuBudget'      => s.GovernorBudgetOverrideCPU__c,
            'soqlBudget'     => s.GovernorBudgetOverrideSOQL__c,
            'dmlBudget'      => s.GovernorBudgetOverrideDML__c
        };
    }

    private static void writeAuditLog(
        String developerName,
        String oldVal,
        String newVal,
        String changeReason,
        String outcome
    ) {
        AuditLogEntry entry = new AuditLogEntry.Builder()
            .actorUserId(UserInfo.getUserId())
            .actionType(AuditLogEntry.ACTION_CONFIG_CHANGE)
            .resourceId(developerName)
            .resourceType('SmokeTestScenario__mdt')
            .oldValue(oldVal)
            .newValue(newVal)
            .changeReason(changeReason)
            .outcome(outcome)
            .build();
        new AuditLogWriter(new DefaultDmlHandler()).logAction(entry);
    }

    private static AuraHandledException auraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    // Sort by ExecutionOrder__c ascending
    private class ExecutionOrderComparator implements Comparator<SmokeTestScenario__mdt> {
        public Integer compare(SmokeTestScenario__mdt a, SmokeTestScenario__mdt b) {
            Decimal orderA = a.ExecutionOrder__c != null ? a.ExecutionOrder__c : 9999;
            Decimal orderB = b.ExecutionOrder__c != null ? b.ExecutionOrder__c : 9999;
            if (orderA < orderB) return -1;
            if (orderA > orderB) return  1;
            return 0;
        }
    }
}
