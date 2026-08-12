public with sharing class ScheduledJobCheck implements IChecklistCheck {

    private static final String CHECK_NAME  = 'Scheduled Job';
    private static final String CHECK_TYPE  = 'SCHEDULED_JOB';
    private static final String CMT_LABEL   = 'Validate Scheduled Jobs';

    public ChecklistResult execute(ChecklistContext ctx) {
        List<String> expectedJobNames = getExpectedJobNames(ctx.checklistConfig);

        if (expectedJobNames.isEmpty()) {
            return checkGeneralScheduledJobs();
        }

        return checkSpecificJobs(expectedJobNames);
    }

    private static List<String> getExpectedJobNames(
        Map<String, SmokeTestChecklist__mdt> configMap
    ) {
        List<String> names = new List<String>();
        for (SmokeTestChecklist__mdt cfg : configMap.values()) {
            if (cfg.IsEnabled__c && CMT_LABEL.equals(cfg.MasterLabel)
                    && String.isNotBlank(cfg.ExpectedResult__c)) {
                for (String name : cfg.ExpectedResult__c.split(',')) {
                    String trimmed = name.trim();
                    if (String.isNotBlank(trimmed)) {
                        names.add(trimmed);
                    }
                }
            }
        }
        return names;
    }

    private static ChecklistResult checkGeneralScheduledJobs() {
        List<CronTrigger> waitingJobs;
        try {
            waitingJobs = [
                SELECT Id, CronJobDetail.Name, State
                FROM CronTrigger
                WHERE CronJobDetail.JobType = '7'
                AND State = 'WAITING'
                WITH SECURITY_ENFORCED
                LIMIT 50
            ];
        } catch (Exception e) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.WARNING,
                'CronTrigger queryable',
                'Query failed',
                'CronTrigger query failed: ' + ErrorSanitizer.sanitize(e.getMessage())
            );
        }

        if (waitingJobs.isEmpty()) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.FAIL,
                'At least one scheduled Apex job in WAITING state',
                'No WAITING jobs found',
                'No scheduled Apex jobs found in WAITING state — verify scheduled jobs are active post-deployment'
            );
        }

        return new ChecklistResult(
            CHECK_NAME, CHECK_TYPE,
            ChecklistResult.Status.PASS,
            'At least one scheduled Apex job in WAITING state',
            waitingJobs.size() + ' WAITING job(s) found',
            waitingJobs.size() + ' scheduled Apex job(s) verified as WAITING'
        );
    }

    private static ChecklistResult checkSpecificJobs(List<String> expectedJobNames) {
        List<CronTrigger> allJobs;
        try {
            allJobs = [
                SELECT Id, CronJobDetail.Name, State
                FROM CronTrigger
                WHERE CronJobDetail.Name IN :expectedJobNames
                WITH SECURITY_ENFORCED
            ];
        } catch (Exception e) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.WARNING,
                'CronTrigger queryable',
                'Query failed',
                'CronTrigger query failed: ' + ErrorSanitizer.sanitize(e.getMessage())
            );
        }

        Map<String, String> jobStateMap = new Map<String, String>();
        for (CronTrigger ct : allJobs) {
            jobStateMap.put(ct.CronJobDetail.Name, ct.State);
        }

        List<String> missing  = new List<String>();
        List<String> notWaiting = new List<String>();
        for (String jobName : expectedJobNames) {
            if (!jobStateMap.containsKey(jobName)) {
                missing.add(jobName);
            } else if (!'WAITING'.equals(jobStateMap.get(jobName))) {
                notWaiting.add(jobName + '(' + jobStateMap.get(jobName) + ')');
            }
        }

        if (!missing.isEmpty() || !notWaiting.isEmpty()) {
            List<String> issues = new List<String>();
            if (!missing.isEmpty()) issues.add('Not scheduled: ' + String.join(missing, ', '));
            if (!notWaiting.isEmpty()) issues.add('Not WAITING: ' + String.join(notWaiting, ', '));
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.FAIL,
                String.join(expectedJobNames, ', ') + ' — all WAITING',
                String.join(issues, '; '),
                'One or more expected scheduled jobs are missing or not in WAITING state. '
                    + String.join(issues, '. ')
            );
        }

        return new ChecklistResult(
            CHECK_NAME, CHECK_TYPE,
            ChecklistResult.Status.PASS,
            String.join(expectedJobNames, ', ') + ' — all WAITING',
            allJobs.size() + ' job(s) verified as WAITING',
            'All ' + expectedJobNames.size() + ' expected scheduled job(s) verified as WAITING'
        );
    }
}
