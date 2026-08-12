/**
 * Processes custom checklist items from SmokeTestChecklist__mdt where
 * CheckType__c = 'query' and IsEnabled__c = true.
 *
 * Each item's Query__c is validated via ChecklistQueryValidator before
 * execution. Results are returned as ChecklistResult instances and are
 * merged into the overall checklist output by ChecklistEvaluator.
 *
 * Audit logging: invoke AuditLogWriter.logPolicyChange() from the admin
 * layer whenever a SmokeTestChecklist__mdt record is created or modified.
 * CustomChecklistProcessor reads but does not write metadata records.
 */
public with sharing class CustomChecklistProcessor {

    @TestVisible private static List<SmokeTestChecklist__mdt> injectedConfig = null;

    private final AuditLogWriter auditWriter;

    public CustomChecklistProcessor() {
        this.auditWriter = null;
    }

    @TestVisible
    CustomChecklistProcessor(AuditLogWriter auditWriter) {
        this.auditWriter = auditWriter;
    }

    /**
     * Iterates allConfig, filters to enabled 'query' type items, validates each
     * query, executes it, and compares the row count against ExpectedResult__c.
     *
     * Comparison: ExpectedResult__c is treated as the expected row-count string.
     * Empty or blank ExpectedResult__c means "any results = PASS".
     *
     * Edge cases:
     *   - null/blank Query__c → WARNING (skipped)
     *   - invalid query → WARNING with validation error detail
     *   - zero rows → FAIL with 'Query returned no results'
     *   - multiple rows → row count used; detail notes multiple rows returned
     *   - query throws → FAIL with sanitized error detail
     */
    public List<ChecklistResult> process(Map<String, SmokeTestChecklist__mdt> allConfig) {
        List<SmokeTestChecklist__mdt> records = injectedConfig != null
            ? injectedConfig
            : new List<SmokeTestChecklist__mdt>(allConfig.values());

        List<ChecklistResult> results = new List<ChecklistResult>();
        for (SmokeTestChecklist__mdt item : records) {
            if (item.IsEnabled__c != true) {
                continue;
            }
            if (!'query'.equalsIgnoreCase(item.CheckType__c)) {
                continue;
            }
            results.add(executeCheck(item));
        }
        return results;
    }

    private ChecklistResult executeCheck(SmokeTestChecklist__mdt item) {
        String checkName = String.isNotBlank(item.CheckName__c)
            ? item.CheckName__c
            : item.DeveloperName;
        String expectedValue = item.ExpectedResult__c;

        if (String.isBlank(item.Query__c)) {
            return new ChecklistResult(
                checkName, 'query', ChecklistResult.Status.WARNING,
                expectedValue, null, 'Query is empty or null — skipping check'
            );
        }

        ValidationResult validation = ChecklistQueryValidator.validate(item.Query__c);
        if (!validation.isValid) {
            return new ChecklistResult(
                checkName, 'query', ChecklistResult.Status.WARNING,
                expectedValue, null,
                'Query validation failed: ' + String.join(validation.errorMessages, '; ')
            );
        }

        try {
            List<SObject> rows = Database.query(item.Query__c);

            if (rows.isEmpty()) {
                return new ChecklistResult(
                    checkName, 'query', ChecklistResult.Status.FAIL,
                    expectedValue, '0', 'Query returned no results'
                );
            }

            String actualValue = String.valueOf(rows.size());
            String detail = rows.size() > 1
                ? 'Multiple rows returned (' + rows.size() + '); using row count for comparison'
                : null;

            ChecklistResult.Status status;
            if (String.isBlank(expectedValue) || expectedValue.trim().equals(actualValue)) {
                status = ChecklistResult.Status.PASS;
            } else {
                status = ChecklistResult.Status.FAIL;
            }

            return new ChecklistResult(checkName, 'query', status, expectedValue, actualValue, detail);

        } catch (Exception e) {
            String sanitized = ErrorSanitizer.sanitize(e.getMessage());
            return new ChecklistResult(
                checkName, 'query', ChecklistResult.Status.FAIL,
                expectedValue, null, 'Query execution failed: ' + sanitized
            );
        }
    }
}
