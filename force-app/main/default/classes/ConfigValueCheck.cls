public with sharing class ConfigValueCheck implements IChecklistCheck {

    private static final String CHECK_NAME     = 'Config Value';
    private static final String CHECK_TYPE     = 'CONFIG_VALUE';
    private static final String CMT_CHECK_TYPE = 'SOQLValidation';

    public ChecklistResult execute(ChecklistContext ctx) {
        List<SmokeTestChecklist__mdt> configs = getEnabledConfigs(ctx.checklistConfig);

        if (configs.isEmpty()) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.WARNING,
                'SOQLValidation checklist entries enabled',
                'No SOQLValidation entries',
                'No enabled SOQLValidation checklist entries found — skipping config value check'
            );
        }

        List<String> failures = new List<String>();
        List<String> errors   = new List<String>();

        for (SmokeTestChecklist__mdt cfg : configs) {
            String query = buildQuery(cfg.Query__c);
            if (query == null) {
                errors.add(cfg.DeveloperName + ': No query defined');
                continue;
            }
            try {
                List<SObject> rows = Database.query(query);
                if (rows.isEmpty()) {
                    failures.add(cfg.DeveloperName);
                }
            } catch (Exception e) {
                errors.add(cfg.DeveloperName + ': ' + ErrorSanitizer.sanitize(e.getMessage()));
            }
        }

        if (!errors.isEmpty()) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.WARNING,
                'All SOQLValidation queries executable',
                'Query error(s): ' + String.join(errors, '; '),
                'One or more config value queries could not be executed: '
                    + String.join(errors, '; ')
            );
        }

        if (!failures.isEmpty()) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.FAIL,
                'All config values match expected state',
                'No records returned for: ' + String.join(failures, ', '),
                'One or more config value queries returned no records: '
                    + String.join(failures, ', ')
            );
        }

        return new ChecklistResult(
            CHECK_NAME, CHECK_TYPE,
            ChecklistResult.Status.PASS,
            'All config values match expected state',
            configs.size() + ' check(s) passed',
            'All ' + configs.size() + ' SOQLValidation check(s) verified successfully'
        );
    }

    private static List<SmokeTestChecklist__mdt> getEnabledConfigs(
        Map<String, SmokeTestChecklist__mdt> configMap
    ) {
        List<SmokeTestChecklist__mdt> result = new List<SmokeTestChecklist__mdt>();
        for (SmokeTestChecklist__mdt cfg : configMap.values()) {
            if (cfg.IsEnabled__c && CMT_CHECK_TYPE.equals(cfg.CheckType__c)) {
                result.add(cfg);
            }
        }
        return result;
    }

    private static String buildQuery(String rawQuery) {
        if (String.isBlank(rawQuery)) return null;
        rawQuery = rawQuery.replace(':orgId', '\'' + UserInfo.getOrganizationId() + '\'');
        rawQuery = rawQuery.replace(':userId', '\'' + UserInfo.getUserId() + '\'');
        return rawQuery;
    }
}
