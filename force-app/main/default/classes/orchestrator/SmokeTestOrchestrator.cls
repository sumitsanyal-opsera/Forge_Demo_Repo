/**
 * Central execution engine for the smoke test suite.
 *
 * Implements the Queueable interface and self-chains to process one scenario per
 * Queueable link, giving each scenario fresh governor limits. Integrates with
 * ScenarioDispatcher, CircuitBreakerService, and GovernorLimitBudget to produce
 * a complete SmokeTestExecution__c record with all SmokeTestResult__c children.
 *
 * Entry point: SmokeTestOrchestrator.startExecution(triggerSource)
 *
 * Queueable chain pattern:
 *   Link 0: pre-deployment security baseline, check CB/timeout, dispatch scenarios[0],
 *            persist result, publish SmokeTestProgress__e, update CB, enqueue link 1
 *   Link N: check CB/timeout, dispatch scenarios[N], ..., enqueue link N+1 (or finalize)
 *   Final:  post-deployment security check, aggregate results, update SmokeTestExecution__c,
 *           publish SmokeTestSecurityComplete__e, publish SmokeTestComplete__e
 *
 * Testability:
 *   bypassEnqueue             = true  — prevents System.enqueueJob() for single-link tests
 *   injectedCb                        — replaces CircuitBreakerService.loadState()
 *   injectedSecurityService           — replaces new SecurityHealthCheckService()
 *   injectedComparator                — replaces new SecurityScoreComparator()
 */
global without sharing class SmokeTestOrchestrator implements Queueable, Database.AllowsCallouts {

    // =========================================================================
    // Constants
    // =========================================================================

    private static final Integer DEFAULT_SUITE_TIMEOUT_SEC = 300;
    private static final String  STATUS_IN_PROGRESS        = 'In Progress';
    private static final String  STATUS_COMPLETED          = 'Completed';
    private static final String  STATUS_FAILED             = 'Failed';
    private static final String  OVERALL_PASS              = 'Pass';
    private static final String  OVERALL_FAIL              = 'Fail';
    private static final String  OVERALL_PARTIAL           = 'Partial';

    // =========================================================================
    // @TestVisible injection flags
    // =========================================================================

    @TestVisible static Boolean                    bypassEnqueue           = false;
    @TestVisible static CircuitBreakerService      injectedCb              = null;
    @TestVisible static Boolean                    injectTopLevelError     = false;
    @TestVisible static ISecurityHealthCheckService injectedSecurityService = null;
    @TestVisible static SecurityScoreComparator    injectedComparator      = null;

    // =========================================================================
    // Immutable instance state (serialized across each Queueable link)
    // =========================================================================

    private final Id                                      executionId;
    private final List<ScenarioDispatcher.ScenarioConfig> scenarios;
    private final Integer                                 currentIndex;
    private final ScenarioDispatcher                      dispatcher;
    private final String                                  triggerSource;
    private final DateTime                                suiteStartTime;
    private final Integer                                 suiteTimeoutSec;
    private final SecurityHealthCheckResult               preSecurityResult;

    // =========================================================================
    // Constructors
    // =========================================================================

    global SmokeTestOrchestrator(
        Id                                        executionId,
        List<ScenarioDispatcher.ScenarioConfig>   scenarios,
        Integer                                   currentIndex,
        ScenarioDispatcher                        dispatcher,
        String                                    triggerSource,
        DateTime                                  suiteStartTime,
        Integer                                   suiteTimeoutSec
    ) {
        this.executionId       = executionId;
        this.scenarios         = (scenarios != null)
            ? scenarios : new List<ScenarioDispatcher.ScenarioConfig>();
        this.currentIndex      = (currentIndex != null) ? currentIndex : 0;
        this.dispatcher        = (dispatcher  != null) ? dispatcher  : new ScenarioDispatcher();
        this.triggerSource     = triggerSource;
        this.suiteStartTime    = (suiteStartTime != null) ? suiteStartTime : DateTime.now();
        this.suiteTimeoutSec   = (suiteTimeoutSec != null && suiteTimeoutSec > 0)
            ? suiteTimeoutSec : DEFAULT_SUITE_TIMEOUT_SEC;
        this.preSecurityResult = null;
    }

    private SmokeTestOrchestrator(
        Id                                        executionId,
        List<ScenarioDispatcher.ScenarioConfig>   scenarios,
        Integer                                   currentIndex,
        ScenarioDispatcher                        dispatcher,
        String                                    triggerSource,
        DateTime                                  suiteStartTime,
        Integer                                   suiteTimeoutSec,
        SecurityHealthCheckResult                 preSecurityResult
    ) {
        this.executionId       = executionId;
        this.scenarios         = (scenarios != null)
            ? scenarios : new List<ScenarioDispatcher.ScenarioConfig>();
        this.currentIndex      = (currentIndex != null) ? currentIndex : 0;
        this.dispatcher        = (dispatcher  != null) ? dispatcher  : new ScenarioDispatcher();
        this.triggerSource     = triggerSource;
        this.suiteStartTime    = (suiteStartTime != null) ? suiteStartTime : DateTime.now();
        this.suiteTimeoutSec   = (suiteTimeoutSec != null && suiteTimeoutSec > 0)
            ? suiteTimeoutSec : DEFAULT_SUITE_TIMEOUT_SEC;
        this.preSecurityResult = preSecurityResult;
    }

    // =========================================================================
    // Static factory — primary entry point
    // =========================================================================

    /**
     * Creates the SmokeTestExecution__c record, loads enabled scenarios, and
     * enqueues the first orchestrator link. Returns the new execution Id.
     *
     * Empty suites are enqueued (not finalized inline) so the pre/post security
     * check still runs in the proper Queueable callout context.
     */
    global static Id startExecution(String triggerSource) {
        ScenarioDispatcher dispatcher = new ScenarioDispatcher();
        List<ScenarioDispatcher.ScenarioConfig> scenarios = dispatcher.getEnabledScenarios();
        Integer timeoutSec = loadSuiteTimeoutSec();
        DateTime startTime = DateTime.now();

        SmokeTestExecution__c exec = new SmokeTestExecution__c(
            Status__c         = STATUS_IN_PROGRESS,
            TriggerSource__c  = triggerSource,
            StartTime__c      = startTime,
            TotalScenarios__c = scenarios.size()
        );
        insert exec;
        Id executionId = exec.Id;

        if (!bypassEnqueue) {
            System.enqueueJob(new SmokeTestOrchestrator(
                executionId, scenarios, 0, dispatcher, triggerSource, startTime, timeoutSec
            ));
        } else if (scenarios.isEmpty()) {
            // Test bypass with empty suite: finalize directly without security check
            doFinalizeForExecution(executionId, startTime);
        }
        return executionId;
    }

    // =========================================================================
    // Queueable — entry point for each chain link
    // =========================================================================

    global void execute(QueueableContext ctx) {
        try {
            innerExecute();
        } catch (Exception e) {
            handleTopLevelError(e);
        }
    }

    // =========================================================================
    // Core execution logic
    // =========================================================================

    private void innerExecute() {

        // Allow tests to exercise the top-level error handler
        if (injectTopLevelError) {
            throw new IllegalStateException('Injected test error for top-level exception coverage');
        }

        // ── Pre-deployment security baseline (first link only) ─────────────────
        SecurityHealthCheckResult effectivePreResult = this.preSecurityResult;
        if (currentIndex == 0 && effectivePreResult == null) {
            effectivePreResult = preExecutionSecurityCapture();
        }

        // ── Empty suite: skip scenario dispatch, go straight to finalization ───
        if (scenarios.isEmpty()) {
            doFinalize(effectivePreResult);
            return;
        }

        // ── Suite timeout check ───────────────────────────────────────────────
        if (isSuiteTimedOut()) {
            insertSkippedResults(currentIndex, scenarios.size(),
                'SKIPPED_SUITE_TIMEOUT',
                'Suite timeout of ' + suiteTimeoutSec + 's exceeded');
            doFinalize(effectivePreResult);
            return;
        }

        // ── Circuit breaker state ──────────────────────────────────────────────
        CircuitBreakerService cb = (injectedCb != null)
            ? injectedCb
            : CircuitBreakerService.loadState(executionId);

        if (cb.isOpen()) {
            insertSkippedResults(currentIndex, scenarios.size(),
                'SKIPPED_CIRCUIT_BREAKER',
                'Circuit breaker is open — skipping remaining scenarios');
            doFinalize(effectivePreResult);
            return;
        }

        // ── Dispatch current scenario ──────────────────────────────────────────
        ScenarioDispatcher.ScenarioConfig cfg = scenarios[currentIndex];
        SmokeTestContext sctx = new SmokeTestContext(
            executionId, null, new Map<String, Object>()
        );
        ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(cfg, sctx);
        ScenarioResult                    sr = dr.scenarioResult;
        GovernorConsumptionReport         gr = dr.consumptionReport;

        // ── Persist result ─────────────────────────────────────────────────────
        String resultStatus = sr.passed ? 'Pass' : deriveResultStatus(sr.errorType);
        SmokeTestResult__c resultRecord = buildResultRecord(
            executionId, sr.scenarioName, resultStatus,
            sr.durationMs, sr.errorType, sr.errorDetail, gr, currentIndex
        );
        insert resultRecord;

        // ── Publish progress event ─────────────────────────────────────────────
        publishProgressEvent(
            executionId, sr.scenarioName, resultStatus,
            currentIndex + 1, scenarios.size()
        );

        // ── Update circuit breaker ─────────────────────────────────────────────
        if (gr != null && (gr.soqlExceeded || gr.dmlExceeded || gr.cpuExceeded)) {
            cb.recordGovernorFailure();
        } else if (sr.passed) {
            cb.recordSuccess();
        } else {
            cb.recordFunctionalFailure();
        }
        cb.saveState();

        // ── Determine next action ──────────────────────────────────────────────
        Integer nextIndex    = currentIndex + 1;
        Boolean moreScenarios = nextIndex < scenarios.size();
        Boolean canContinue   = cb.isClosed() && !isSuiteTimedOut();

        if (moreScenarios && canContinue && !bypassEnqueue) {
            try {
                System.enqueueJob(new SmokeTestOrchestrator(
                    executionId, scenarios, nextIndex, dispatcher,
                    triggerSource, suiteStartTime, suiteTimeoutSec, effectivePreResult
                ));
            } catch (System.AsyncException ae) {
                // Flex queue full — mark remaining scenarios as SKIPPED_QUEUE_FULL
                insertSkippedResults(nextIndex, scenarios.size(),
                    'SKIPPED_QUEUE_FULL',
                    'Async job queue full: ' + ae.getMessage());
                doFinalize(effectivePreResult);
            }
        } else {
            // No more scenarios, or circuit breaker just opened, or timeout, or bypass
            if (moreScenarios && !canContinue) {
                // Circuit tripped or timed out — skip remaining
                String skipType = cb.isOpen()
                    ? 'SKIPPED_CIRCUIT_BREAKER'
                    : 'SKIPPED_SUITE_TIMEOUT';
                String skipMsg = cb.isOpen()
                    ? 'Circuit breaker tripped — skipping remaining scenarios'
                    : 'Suite timeout exceeded — skipping remaining scenarios';
                insertSkippedResults(nextIndex, scenarios.size(), skipType, skipMsg);
            }
            doFinalize(effectivePreResult);
        }
    }

    // =========================================================================
    // Top-level error handler
    // =========================================================================

    private void handleTopLevelError(Exception e) {
        Long durationMs = DateTime.now().getTime() - suiteStartTime.getTime();
        try {
            update new SmokeTestExecution__c(
                Id                 = executionId,
                Status__c          = STATUS_FAILED,
                EndTime__c         = DateTime.now(),
                ExecutionTimeMs__c = durationMs
            );
        } catch (Exception inner) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestOrchestrator: could not update execution to Failed: '
                + inner.getMessage());
        }
        try {
            EventBus.publish(new SmokeTestComplete__e(
                ExecutionId__c     = String.valueOf(executionId),
                OverallResult__c   = 'Error',
                PassedCount__c     = 0,
                FailedCount__c     = 0,
                ExecutionTimeMs__c = durationMs
            ));
        } catch (Exception evtErr) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestOrchestrator: could not publish error SmokeTestComplete__e: '
                + evtErr.getMessage());
        }
        System.debug(LoggingLevel.ERROR,
            'SmokeTestOrchestrator.execute: unhandled exception — ' + e.getMessage());
    }

    // =========================================================================
    // Finalization
    // =========================================================================

    private void doFinalize(SecurityHealthCheckResult preResult) {
        postExecutionSecurityCheck(preResult);
        doFinalizeForExecution(executionId, suiteStartTime);
    }

    @TestVisible
    private static void doFinalizeForExecution(Id execId, DateTime startTime) {
        List<SmokeTestResult__c> allResults = [
            SELECT Status__c
            FROM SmokeTestResult__c
            WHERE Execution__c = :execId
        ];

        Integer passed   = 0;
        Integer failed   = 0;
        Integer timedOut = 0;
        Integer skipped  = 0;

        for (SmokeTestResult__c r : allResults) {
            if      (r.Status__c == 'Pass')    { passed++; }
            else if (r.Status__c == 'Fail')    { failed++; }
            else if (r.Status__c == 'Timeout') { timedOut++; }
            else if (r.Status__c == 'Skipped') { skipped++; }
        }

        Integer totalNonSkipped = passed + failed + timedOut;
        String  overallResult;

        if (totalNonSkipped == 0) {
            // All skipped or no results — treat as pass (empty suite or circuit breaker with 0 dispatched)
            overallResult = OVERALL_PASS;
        } else if (failed + timedOut == 0) {
            overallResult = OVERALL_PASS;
        } else if (passed == 0) {
            overallResult = OVERALL_FAIL;
        } else {
            overallResult = OVERALL_PARTIAL;
        }

        Long durationMs = (startTime != null)
            ? (DateTime.now().getTime() - startTime.getTime())
            : 0L;

        try {
            update new SmokeTestExecution__c(
                Id                 = execId,
                Status__c          = STATUS_COMPLETED,
                EndTime__c         = DateTime.now(),
                ExecutionTimeMs__c = durationMs,
                TotalScenarios__c  = allResults.size(),
                PassedScenarios__c = passed,
                FailedScenarios__c = failed + timedOut,
                OverallResult__c   = overallResult
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestOrchestrator.doFinalizeForExecution: DML failed: '
                + e.getMessage());
        }

        try {
            EventBus.publish(new SmokeTestComplete__e(
                ExecutionId__c         = String.valueOf(execId),
                OverallResult__c       = overallResult,
                PassedCount__c         = passed,
                FailedCount__c         = failed + timedOut,
                ExecutionTimeMs__c     = durationMs,
                RollbackRecommended__c = (overallResult == OVERALL_FAIL
                                         || overallResult == OVERALL_PARTIAL)
            ));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestOrchestrator.doFinalizeForExecution: could not publish SmokeTestComplete__e: '
                + e.getMessage());
        }
    }

    // =========================================================================
    // Security health check integration
    // =========================================================================

    private SecurityHealthCheckResult preExecutionSecurityCapture() {
        try {
            ISecurityHealthCheckService svc = (injectedSecurityService != null)
                ? injectedSecurityService
                : new SecurityHealthCheckService();
            return svc.captureScore();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestOrchestrator.preExecutionSecurityCapture: ' + e.getMessage());
            return SecurityHealthCheckResult.error(
                'Pre-deployment capture failed: ' + e.getMessage());
        }
    }

    private void postExecutionSecurityCheck(SecurityHealthCheckResult preResult) {
        // Capture post-deployment score
        SecurityHealthCheckResult postResult;
        try {
            ISecurityHealthCheckService svc = (injectedSecurityService != null)
                ? injectedSecurityService
                : new SecurityHealthCheckService();
            postResult = svc.captureScore();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestOrchestrator.postExecutionSecurityCheck.capture: ' + e.getMessage());
            postResult = SecurityHealthCheckResult.error(
                'Post-deployment capture failed: ' + e.getMessage());
        }

        // Compare pre vs post
        SecurityComparisonResult comp;
        try {
            SecurityScoreComparator comparator = (injectedComparator != null)
                ? injectedComparator
                : new SecurityScoreComparator();
            comp = comparator.compare(preResult, postResult);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestOrchestrator.postExecutionSecurityCheck.compare: ' + e.getMessage());
            SecurityComparisonResult errResult = new SecurityComparisonResult();
            errResult.status             = SecurityComparisonResult.Status.Error;
            errResult.violationType      = SecurityComparisonResult.ViolationType.None;
            errResult.preScore           = (preResult  != null) ? preResult.overallScore  : null;
            errResult.postScore          = (postResult != null) ? postResult.overallScore : null;
            errResult.scoreDelta         = null;
            errResult.configuredThreshold = 80;
            errResult.configuredMaxDrop  = 5;
            errResult.changedCategories  = new List<String>();
            errResult.detailMessage      = 'Comparator exception: ' + e.getMessage();
            comp = errResult;
        }

        // Persist result and publish event
        persistSecurityScore(comp, postResult);
        publishSecurityCompleteEvent(comp);
    }

    private void persistSecurityScore(
        SecurityComparisonResult comp,
        SecurityHealthCheckResult postResult
    ) {
        // Guard: check DML headroom before attempting insert
        if (Limits.getDmlStatements() >= Limits.getLimitDmlStatements() - 2) {
            System.debug(LoggingLevel.WARN,
                'SmokeTestOrchestrator: DML limit approaching — skipping SmokeTestSecurityScore__c insert');
            return;
        }

        String thresholdStatusStr = compStatusToString(comp.status);
        Boolean thresholdMet = (comp.status == SecurityComparisonResult.Status.Pass);

        String riskCategoriesJson = null;
        if (comp.changedCategories != null && !comp.changedCategories.isEmpty()) {
            riskCategoriesJson = JSON.serialize(comp.changedCategories);
        }

        String rawResponse = null;
        if (postResult != null && postResult.diagnosticMessage != null) {
            rawResponse = postResult.diagnosticMessage;
            if (rawResponse.length() > 32000) {
                rawResponse = rawResponse.substring(0, 32000);
            }
        }

        SmokeTestSecurityScore__c score = new SmokeTestSecurityScore__c(
            Execution__c          = executionId,
            PreDeploymentScore__c = comp.preScore  != null ? comp.preScore  : -1,
            PostDeploymentScore__c= comp.postScore != null ? comp.postScore : -1,
            AbsoluteThreshold__c  = comp.configuredThreshold != null
                                        ? comp.configuredThreshold : 80,
            RelativeThreshold__c  = comp.configuredMaxDrop != null
                                        ? comp.configuredMaxDrop : 5,
            ThresholdMet__c       = thresholdMet,
            ThresholdStatus__c    = thresholdStatusStr,
            CheckedAt__c          = DateTime.now(),
            IntegrationUser__c    = UserInfo.getUserId(),
            RiskCategories__c     = riskCategoriesJson,
            RawResponse__c        = rawResponse
        );

        try {
            insert score;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestOrchestrator.persistSecurityScore: DML failed: ' + e.getMessage());
        }
    }

    private void publishSecurityCompleteEvent(SecurityComparisonResult comp) {
        try {
            List<Database.SaveResult> results = EventBus.publish(
                new SmokeTestSecurityComplete__e(
                    ExecutionId__c    = String.valueOf(executionId),
                    ThresholdStatus__c= compStatusToString(comp.status),
                    Timestamp__c      = DateTime.now()
                )
            );
            for (Database.SaveResult sr : results) {
                if (!sr.isSuccess()) {
                    for (Database.Error err : sr.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'SmokeTestOrchestrator.publishSecurityCompleteEvent: '
                            + err.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestOrchestrator.publishSecurityCompleteEvent: ' + e.getMessage());
        }
    }

    private static String compStatusToString(SecurityComparisonResult.Status status) {
        if (status == SecurityComparisonResult.Status.Pass)  { return 'Pass'; }
        if (status == SecurityComparisonResult.Status.Fail)  { return 'Fail'; }
        return 'Error';
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private static Integer loadSuiteTimeoutSec() {
        try {
            List<SmokeTestConfig__mdt> configs = [
                SELECT SuiteTimeoutSec__c
                FROM SmokeTestConfig__mdt
                WHERE DeveloperName = 'Default'
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!configs.isEmpty() && configs[0].SuiteTimeoutSec__c != null) {
                return Integer.valueOf(configs[0].SuiteTimeoutSec__c);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'SmokeTestOrchestrator: could not load SuiteTimeoutSec__c — using default: '
                + e.getMessage());
        }
        return DEFAULT_SUITE_TIMEOUT_SEC;
    }

    private Boolean isSuiteTimedOut() {
        Long elapsedMs = DateTime.now().getTime() - suiteStartTime.getTime();
        return elapsedMs >= ((Long) suiteTimeoutSec * 1000L);
    }

    private void insertSkippedResults(Integer fromIdx, Integer toIdx, String errorType, String message) {
        if (fromIdx >= toIdx) { return; }
        List<SmokeTestResult__c> skipped = new List<SmokeTestResult__c>();
        for (Integer i = fromIdx; i < toIdx; i++) {
            ScenarioDispatcher.ScenarioConfig cfg = scenarios[i];
            skipped.add(buildResultRecord(
                executionId, cfg.scenarioName, 'Skipped', 0L, errorType, message, null, i
            ));
        }
        try {
            insert skipped;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SmokeTestOrchestrator.insertSkippedResults: DML failed: ' + e.getMessage());
        }
    }

    private static SmokeTestResult__c buildResultRecord(
        Id                        execId,
        String                    scenarioName,
        String                    status,
        Long                      durationMs,
        String                    errorType,
        String                    errorDetail,
        GovernorConsumptionReport report,
        Integer                   execOrder
    ) {
        String errorMsg = null;
        if (errorType != null || errorDetail != null) {
            errorMsg = (errorType != null ? '[' + errorType + '] ' : '')
                + (errorDetail != null ? errorDetail : '');
            if (errorMsg.length() > 32000) {
                errorMsg = errorMsg.substring(0, 32000);
            }
        }

        SmokeTestResult__c r = new SmokeTestResult__c(
            Execution__c       = execId,
            ScenarioName__c    = scenarioName,
            Status__c          = status,
            ExecutionTimeMs__c = durationMs,
            ErrorMessage__c    = errorMsg,
            ExecutionOrder__c  = execOrder
        );

        if (report != null) {
            r.SOQLQueries__c          = report.soqlUsed;
            r.DMLStatements__c        = report.dmlUsed;
            r.CPUTimeMs__c            = report.cpuUsed;
            r.GovernorLimitExceeded__c =
                report.soqlExceeded || report.dmlExceeded || report.cpuExceeded;
        }
        return r;
    }

    private static void publishProgressEvent(
        Id      execId,
        String  scenarioName,
        String  resultStatus,
        Integer completedCount,
        Integer totalCount
    ) {
        try {
            EventBus.publish(new SmokeTestProgress__e(
                ExecutionId__c    = String.valueOf(execId),
                ScenarioName__c   = scenarioName,
                ScenarioStatus__c = resultStatus,
                CompletedCount__c = completedCount,
                TotalCount__c     = totalCount
            ));
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'SmokeTestOrchestrator: failed to publish SmokeTestProgress__e: '
                + e.getMessage());
        }
    }

    private static String deriveResultStatus(String errorType) {
        if (errorType == null)              { return 'Fail'; }
        if (errorType == 'TIMED_OUT')       { return 'Timeout'; }
        if (errorType.startsWith('SKIPPED_')) { return 'Skipped'; }
        return 'Fail';
    }
}
