/**
 * AuraEnabled Apex controller for the SettingsPage LWC.
 * Reads and writes all global smoke test parameters from/to the SmokeTestConfig__mdt
 * 'Default' record via MetadataDeployService (single atomic deployment).
 *
 * All writes are audit-logged via AuditLogWriter. Rollback policy changes require
 * a non-blank changeReason (enforced server-side).
 */
public with sharing class SettingsController {

    private static final String CONFIG_RECORD = 'Default';

    // Minimum audit log retention (SOC 2 / ISO 27001 compliance floor)
    @TestVisible static final Integer AUDIT_LOG_RETENTION_MIN = 365;

    // Validation rules: field API name → [min, max] for numeric fields
    // Boolean fields need no range validation
    private static final Map<String, List<Integer>> NUMERIC_RANGES = new Map<String, List<Integer>>{
        'SuiteTimeoutSec__c'              => new List<Integer>{ 60,   600  },
        'PerScenarioTimeoutSec__c'        => new List<Integer>{ 10,   120  },
        'GovernorBudgetCPUMs__c'          => new List<Integer>{ 1000, 10000},
        'GovernorBudgetSOQL__c'           => new List<Integer>{ 10,   200  },
        'GovernorBudgetDML__c'            => new List<Integer>{ 10,   150  },
        'CircuitBreakerThreshold__c'      => new List<Integer>{ 1,    10   },
        'SecurityScoreAbsoluteThreshold__c'=> new List<Integer>{ 0,   100  },
        'SecurityScoreRelativeThreshold__c'=> new List<Integer>{ 0,   50   },
        'DataRetentionDaysInternal__c'    => new List<Integer>{ 1,    3650 },
        'DataRetentionDaysConfidential__c'=> new List<Integer>{ 1,    3650 },
        'DataRetentionDaysSecurityScores__c'=>new List<Integer>{ 1,   3650 },
        'DataRetentionDaysAuditLogs__c'   => new List<Integer>{ 365,  3650 }
    };

    private static final Set<String> VALID_ROLLBACK_POLICIES = new Set<String>{
        'Recommend Only',
        'Auto-Rollback on Critical Failure',
        'Manual Approval Required'
    };

    // =========================================================================
    // Read
    // =========================================================================

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getSettings() {
        try {
            checkAdminPermission();
            SmokeTestConfig__mdt cfg = SmokeTestConfig__mdt.getInstance(CONFIG_RECORD);
            if (cfg == null) {
                throw auraException(
                    'Default SmokeTestConfig__mdt record not found. Please deploy the package defaults.');
            }
            return toMap(cfg);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            throw auraException(ex.getMessage());
        }
    }

    // =========================================================================
    // Save (batch)
    // =========================================================================

    @AuraEnabled
    public static Map<String, Object> saveSettings(
        Map<String, Object> changedFields,
        String changeReason
    ) {
        try {
            checkAdminPermission();
            if (changedFields == null || changedFields.isEmpty()) {
                throw auraException('No changes to save');
            }

            // Rollback policy change requires a non-blank change reason
            if (changedFields.containsKey('DefaultRollbackPolicy__c') &&
                String.isBlank(changeReason)) {
                throw auraException(
                    'A change reason is required when modifying the Rollback Policy.');
            }

            // Collect validation errors
            Map<String, String> fieldErrors = validateFields(changedFields);
            if (!fieldErrors.isEmpty()) {
                throw auraException(JSON.serialize(fieldErrors));
            }

            // Read current values for audit log old-values
            SmokeTestConfig__mdt current = SmokeTestConfig__mdt.getInstance(CONFIG_RECORD);
            Map<String, Object> currentMap = current != null ? toMap(current) : new Map<String, Object>();

            // Build field values for deployment
            Map<String, Object> deployFields = new Map<String, Object>();
            for (String fieldName : changedFields.keySet()) {
                deployFields.put(fieldName, changedFields.get(fieldName));
            }

            MetadataDeployService.DeployResult deploy = MetadataDeployService.upsertCustomMetadata(
                'SmokeTestConfig__mdt',
                CONFIG_RECORD,
                'Default',
                deployFields
            );

            if (!deploy.success) {
                throw auraException('Metadata deployment failed: ' + deploy.errorMessage);
            }

            // Write one audit log entry per changed field
            String reason = String.isBlank(changeReason) ? 'Settings updated via Settings page' : changeReason;
            List<AuditLogEntry> entries = new List<AuditLogEntry>();
            for (String fieldName : changedFields.keySet()) {
                String oldVal = currentMap.containsKey(fieldName)
                    ? String.valueOf(currentMap.get(fieldName)) : null;
                String newVal = String.valueOf(changedFields.get(fieldName));
                entries.add(new AuditLogEntry.Builder()
                    .actorUserId(UserInfo.getUserId())
                    .actionType(AuditLogEntry.ACTION_CONFIG_CHANGE)
                    .resourceId(CONFIG_RECORD + '.' + fieldName)
                    .resourceType('SmokeTestConfig__mdt')
                    .oldValue(oldVal)
                    .newValue(newVal)
                    .changeReason(reason)
                    .outcome('SUCCESS')
                    .build());
            }
            new AuditLogWriter(new DefaultDmlHandler()).logActions(entries);

            return new Map<String, Object>{ 'success' => true, 'jobId' => deploy.jobId };

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
                'You must have the SmokeTest_Admin permission set to manage settings.');
        }
    }

    private static Map<String, String> validateFields(Map<String, Object> fields) {
        Map<String, String> errors = new Map<String, String>();

        for (String fieldName : fields.keySet()) {
            Object rawValue = fields.get(fieldName);

            // Numeric range validation
            if (NUMERIC_RANGES.containsKey(fieldName)) {
                Integer val;
                try {
                    val = Integer.valueOf(String.valueOf(rawValue));
                } catch (Exception ex) {
                    errors.put(fieldName, fieldName.removeEnd('__c') + ' must be a whole number');
                    continue;
                }
                List<Integer> range = NUMERIC_RANGES.get(fieldName);
                Integer minVal = range[0];
                Integer maxVal = range[1];
                if (val < minVal || val > maxVal) {
                    String label = fieldLabel(fieldName);
                    errors.put(fieldName,
                        label + ' must be between ' + minVal + ' and ' + maxVal + '. Got: ' + val);
                }
                // Special enforcement: audit log retention floor
                if (fieldName == 'DataRetentionDaysAuditLogs__c' && val < AUDIT_LOG_RETENTION_MIN) {
                    errors.put(fieldName,
                        'Audit Log retention cannot be less than ' + AUDIT_LOG_RETENTION_MIN +
                        ' days (SOC 2 / ISO 27001 compliance requirement)');
                }
                continue;
            }

            // Rollback policy allow-list
            if (fieldName == 'DefaultRollbackPolicy__c') {
                String policy = String.valueOf(rawValue);
                if (!VALID_ROLLBACK_POLICIES.contains(policy)) {
                    errors.put(fieldName,
                        'Invalid Rollback Policy. Valid values: ' +
                        String.join(new List<String>(VALID_ROLLBACK_POLICIES), ', '));
                }
                continue;
            }

            // Boolean fields — no further validation needed
        }

        return errors;
    }

    private static String fieldLabel(String fieldApiName) {
        Map<String, String> labels = new Map<String, String>{
            'SuiteTimeoutSec__c'               => 'Suite Timeout (seconds)',
            'PerScenarioTimeoutSec__c'          => 'Scenario Timeout (seconds)',
            'GovernorBudgetCPUMs__c'            => 'CPU Budget (ms)',
            'GovernorBudgetSOQL__c'             => 'SOQL Budget',
            'GovernorBudgetDML__c'              => 'DML Budget',
            'CircuitBreakerThreshold__c'        => 'Circuit Breaker Threshold',
            'SecurityScoreAbsoluteThreshold__c' => 'Security Minimum Threshold',
            'SecurityScoreRelativeThreshold__c' => 'Maximum Score Drop',
            'DataRetentionDaysInternal__c'      => 'Detail Log Retention (days)',
            'DataRetentionDaysConfidential__c'  => 'Result Summary Retention (days)',
            'DataRetentionDaysSecurityScores__c'=> 'Security Score Retention (days)',
            'DataRetentionDaysAuditLogs__c'     => 'Audit Log Retention (days)'
        };
        return labels.containsKey(fieldApiName)
            ? labels.get(fieldApiName)
            : fieldApiName.removeEnd('__c');
    }

    private static Map<String, Object> toMap(SmokeTestConfig__mdt cfg) {
        return new Map<String, Object>{
            'SuiteTimeoutSec__c'               => cfg.SuiteTimeoutSec__c,
            'PerScenarioTimeoutSec__c'          => cfg.PerScenarioTimeoutSec__c,
            'GovernorBudgetCPUMs__c'            => cfg.GovernorBudgetCPUMs__c,
            'GovernorBudgetSOQL__c'             => cfg.GovernorBudgetSOQL__c,
            'GovernorBudgetDML__c'              => cfg.GovernorBudgetDML__c,
            'CircuitBreakerThreshold__c'        => cfg.CircuitBreakerThreshold__c,
            'SecurityScoreAbsoluteThreshold__c' => cfg.SecurityScoreAbsoluteThreshold__c,
            'SecurityScoreRelativeThreshold__c' => cfg.SecurityScoreRelativeThreshold__c,
            'SecurityHealthCheckEnabled__c'     => cfg.SecurityHealthCheckEnabled__c,
            'DefaultRollbackPolicy__c'          => cfg.DefaultRollbackPolicy__c,
            'DryRunMode__c'                     => cfg.DryRunMode__c,
            'ShadowMode__c'                     => cfg.ShadowMode__c,
            'AutoTriggerEnabled__c'             => cfg.AutoTriggerEnabled__c,
            'DataRetentionDaysInternal__c'      => cfg.DataRetentionDaysInternal__c,
            'DataRetentionDaysConfidential__c'  => cfg.DataRetentionDaysConfidential__c,
            'DataRetentionDaysSecurityScores__c'=> cfg.DataRetentionDaysSecurityScores__c,
            'DataRetentionDaysAuditLogs__c'     => cfg.DataRetentionDaysAuditLogs__c
        };
    }

    private static AuraHandledException auraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
