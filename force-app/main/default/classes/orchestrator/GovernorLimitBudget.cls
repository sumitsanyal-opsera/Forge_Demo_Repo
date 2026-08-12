/**
 * Per-scenario governor limit consumption tracker.
 *
 * Usage pattern (called by ScenarioDispatcher around each scenario):
 *   GovernorLimitBudget tracker = new GovernorLimitBudget();
 *   tracker.captureBaseline();           // immediately before scenario.execute()
 *   scenario.execute(context);
 *   Boolean ok = tracker.isWithinBudget(config);
 *   GovernorConsumptionReport report = tracker.getConsumptionReport(config);
 *
 * Design notes:
 *   - All Limits reads are zero-cost (no SOQL, no DML, no callouts).
 *   - In a Queueable chain, Limits reset per job; captureBaseline() at the
 *     start of each Queueable execute() correctly reflects per-job consumption.
 *   - captureBaseline() may be called multiple times; each call overwrites
 *     the previous baseline (does not accumulate).
 *   - Both isWithinBudget() and getConsumptionReport() throw IllegalStateException
 *     when called before captureBaseline().
 *   - Budget comparisons use <= (inclusive); GovernorConsumptionReport exceeded
 *     flags use > (strict) — at exact boundary the scenario is within budget and
 *     not flagged as exceeded.
 */
global with sharing class GovernorLimitBudget {

    private Integer baselineSoql     = 0;
    private Integer baselineDml      = 0;
    private Integer baselineCpu      = 0;
    private Boolean baselineCaptured = false;

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Capture the current Limits values as the baseline for this scenario.
     * Must be called immediately before scenario execution begins.
     * Safe to call multiple times — overwrites the previous baseline.
     */
    global void captureBaseline() {
        baselineSoql     = Limits.getQueries();
        baselineDml      = Limits.getDmlStatements();
        baselineCpu      = Limits.getCpuTime();
        baselineCaptured = true;
    }

    /**
     * Returns true if consumption since baseline is within all three budget
     * dimensions (SOQL, DML, CPU). Uses inclusive comparison (used <= budget).
     *
     * @throws IllegalStateException if captureBaseline() was not called first.
     */
    global Boolean isWithinBudget(GovernorBudgetConfig config) {
        assertBaselineCaptured('isWithinBudget');
        return (Limits.getQueries()       - baselineSoql) <= config.soqlBudget
            && (Limits.getDmlStatements() - baselineDml)  <= config.dmlBudget
            && (Limits.getCpuTime()       - baselineCpu)  <= config.cpuBudgetMs;
    }

    /**
     * Returns a GovernorConsumptionReport reflecting consumption since baseline
     * against the provided GovernorBudgetConfig.
     *
     * @throws IllegalStateException if captureBaseline() was not called first.
     */
    global GovernorConsumptionReport getConsumptionReport(GovernorBudgetConfig config) {
        assertBaselineCaptured('getConsumptionReport');
        return new GovernorConsumptionReport(
            Limits.getQueries()       - baselineSoql,
            Limits.getDmlStatements() - baselineDml,
            Limits.getCpuTime()       - baselineCpu,
            config.soqlBudget,
            config.dmlBudget,
            config.cpuBudgetMs
        );
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private void assertBaselineCaptured(String callerMethod) {
        if (!baselineCaptured) {
            throw new IllegalStateException(
                'captureBaseline() must be called before ' + callerMethod + '()');
        }
    }
}
