/**
 * Strategy-pattern routing layer for ISmokeTestScenario dispatch.
 *
 * Reads enabled scenarios from SmokeTestScenario__mdt, dynamically instantiates
 * each ISmokeTestScenario implementation by class name, wraps execution with
 * GovernorLimitBudget tracking and ScenarioTimeoutHandler enforcement, and
 * returns structured DispatchResult objects. Never throws — always returns a result.
 *
 * Usage pattern (called by the orchestrator Queueable):
 *   ScenarioDispatcher dispatcher = new ScenarioDispatcher();
 *   for (ScenarioDispatcher.ScenarioConfig cfg : dispatcher.getEnabledScenarios()) {
 *       ScenarioDispatcher.DispatchResult dr = dispatcher.dispatch(cfg, context);
 *       // evaluate dr.consumptionReport for circuit breaker
 *   }
 *
 * Testability:
 *   Use the @TestVisible constructor to inject a list of ScenarioConfig objects,
 *   bypassing the SmokeTestScenario__mdt SOQL query (CMT cannot be DML-created in tests).
 */
global with sharing class ScenarioDispatcher {

    // =========================================================================
    // ScenarioConfig — mirrors SmokeTestScenario__mdt for testable injection
    // =========================================================================

    global class ScenarioConfig implements Comparable {
        global String  scenarioName;
        global String  scenarioClass;
        global Integer executionOrder;
        global Boolean isEnabled;
        global Boolean isCritical;
        global Integer timeoutOverrideSec;
        global Integer governorBudgetOverrideCPU;
        global Integer governorBudgetOverrideSOQL;
        global Integer governorBudgetOverrideDML;

        global ScenarioConfig(
            String  scenarioName,
            String  scenarioClass,
            Integer executionOrder,
            Boolean isEnabled,
            Boolean isCritical,
            Integer timeoutOverrideSec,
            Integer governorBudgetOverrideCPU,
            Integer governorBudgetOverrideSOQL,
            Integer governorBudgetOverrideDML
        ) {
            this.scenarioName               = scenarioName;
            this.scenarioClass              = scenarioClass;
            this.executionOrder             = executionOrder;
            this.isEnabled                  = (isEnabled  != null) ? isEnabled  : false;
            this.isCritical                 = (isCritical != null) ? isCritical : false;
            this.timeoutOverrideSec         = timeoutOverrideSec;
            this.governorBudgetOverrideCPU  = governorBudgetOverrideCPU;
            this.governorBudgetOverrideSOQL = governorBudgetOverrideSOQL;
            this.governorBudgetOverrideDML  = governorBudgetOverrideDML;
        }

        global Integer compareTo(Object other) {
            ScenarioConfig o = (ScenarioConfig) other;
            Integer a = (this.executionOrder != null) ? this.executionOrder : 0;
            Integer b = (o.executionOrder    != null) ? o.executionOrder    : 0;
            if (a < b) return -1;
            if (a > b) return  1;
            return 0;
        }
    }

    // =========================================================================
    // DispatchResult — bundles ScenarioResult with GovernorConsumptionReport
    // =========================================================================

    global class DispatchResult {
        global final ScenarioResult            scenarioResult;
        global final GovernorConsumptionReport consumptionReport; // null for pre-execution failures

        global DispatchResult(ScenarioResult result, GovernorConsumptionReport report) {
            this.scenarioResult    = result;
            this.consumptionReport = report;
        }
    }

    // =========================================================================
    // State
    // =========================================================================

    private final List<ScenarioConfig> injectedConfigs;

    // =========================================================================
    // Constructors
    // =========================================================================

    global ScenarioDispatcher() {
        this.injectedConfigs = null;
    }

    @TestVisible
    private ScenarioDispatcher(List<ScenarioConfig> injectedConfigs) {
        this.injectedConfigs = injectedConfigs;
    }

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Returns an ordered (by ExecutionOrder__c ASC) list of enabled scenario
     * configurations. Uses the injected list if provided; otherwise queries
     * SmokeTestScenario__mdt.
     */
    global List<ScenarioConfig> getEnabledScenarios() {
        if (injectedConfigs != null) {
            List<ScenarioConfig> enabled = new List<ScenarioConfig>();
            for (ScenarioConfig cfg : injectedConfigs) {
                if (cfg.isEnabled == true) {
                    enabled.add(cfg);
                }
            }
            enabled.sort();
            return enabled;
        }

        List<SmokeTestScenario__mdt> records = [
            SELECT DeveloperName,
                   ScenarioClass__c,
                   ExecutionOrder__c,
                   IsEnabled__c,
                   IsCritical__c,
                   TimeoutOverrideSec__c,
                   GovernorBudgetOverrideCPU__c,
                   GovernorBudgetOverrideSOQL__c,
                   GovernorBudgetOverrideDML__c
            FROM SmokeTestScenario__mdt
            WHERE IsEnabled__c = true
            ORDER BY ExecutionOrder__c ASC
        ];

        List<ScenarioConfig> configs = new List<ScenarioConfig>();
        for (SmokeTestScenario__mdt r : records) {
            configs.add(new ScenarioConfig(
                r.DeveloperName,
                r.ScenarioClass__c,
                r.ExecutionOrder__c          != null ? Integer.valueOf(r.ExecutionOrder__c)          : 0,
                r.IsEnabled__c,
                r.IsCritical__c,
                r.TimeoutOverrideSec__c      != null ? Integer.valueOf(r.TimeoutOverrideSec__c)      : null,
                r.GovernorBudgetOverrideCPU__c  != null ? Integer.valueOf(r.GovernorBudgetOverrideCPU__c)  : null,
                r.GovernorBudgetOverrideSOQL__c != null ? Integer.valueOf(r.GovernorBudgetOverrideSOQL__c) : null,
                r.GovernorBudgetOverrideDML__c  != null ? Integer.valueOf(r.GovernorBudgetOverrideDML__c)  : null
            ));
        }
        return configs;
    }

    /**
     * AC-1 compatible overload. Instantiates scenarioClassName, executes it with
     * default governor budget, and returns a ScenarioResult. Never throws.
     */
    global ScenarioResult dispatch(String scenarioClassName, SmokeTestContext context) {
        ScenarioConfig cfg = new ScenarioConfig(
            scenarioClassName, scenarioClassName, 0, true, false, null, null, null, null
        );
        return dispatch(cfg, context).scenarioResult;
    }

    /**
     * Full-featured dispatch. Checks the disabled flag, dynamically instantiates
     * the scenario, captures governor baselines, starts the timeout timer, executes
     * the scenario, and returns a DispatchResult with the consumption report attached.
     *
     * Error types returned:
     *   SKIPPED_DISABLED      — config.isEnabled == false
     *   CLASS_NOT_FOUND       — Type.forName returned null or scenarioClass is blank
     *   INSTANTIATION_ERROR   — newInstance() threw or class does not implement ISmokeTestScenario
     *   TIMED_OUT             — ScenarioTimeoutException caught after/during execute()
     *   DML_EXCEPTION         — DmlException escaped from execute()
     *   QUERY_EXCEPTION       — QueryException escaped from execute()
     *   UNEXPECTED_ERROR      — any other Exception escaped from execute()
     */
    global DispatchResult dispatch(ScenarioConfig config, SmokeTestContext context) {

        // ── Disabled check ────────────────────────────────────────────────────
        if (!config.isEnabled) {
            return new DispatchResult(
                ScenarioResult.failure(
                    config.scenarioName, 0L, 'SKIPPED_DISABLED',
                    'Scenario ' + config.scenarioName + ' is disabled in SmokeTestScenario__mdt'
                ),
                null
            );
        }

        // ── Class resolution ──────────────────────────────────────────────────
        if (String.isBlank(config.scenarioClass)) {
            return new DispatchResult(
                ScenarioResult.failure(
                    config.scenarioName, 0L, 'CLASS_NOT_FOUND',
                    'scenarioClass is blank for scenario: ' + config.scenarioName
                ),
                null
            );
        }

        Type scenarioType = Type.forName(config.scenarioClass);
        if (scenarioType == null) {
            return new DispatchResult(
                ScenarioResult.failure(
                    config.scenarioName, 0L, 'CLASS_NOT_FOUND',
                    'Scenario class not found: ' + config.scenarioClass
                ),
                null
            );
        }

        // ── Instantiation ─────────────────────────────────────────────────────
        Object rawInstance;
        try {
            rawInstance = scenarioType.newInstance();
        } catch (TypeException e) {
            return new DispatchResult(
                ScenarioResult.failure(
                    config.scenarioName, 0L, 'INSTANTIATION_ERROR',
                    cap(e.getMessage(), 1000)
                ),
                null
            );
        } catch (Exception e) {
            return new DispatchResult(
                ScenarioResult.failure(
                    config.scenarioName, 0L, 'INSTANTIATION_ERROR',
                    cap(ErrorSanitizer.sanitize(e.getMessage()), 1000)
                ),
                null
            );
        }

        if (!(rawInstance instanceof ISmokeTestScenario)) {
            return new DispatchResult(
                ScenarioResult.failure(
                    config.scenarioName, 0L, 'INSTANTIATION_ERROR',
                    'Class does not implement ISmokeTestScenario: ' + config.scenarioClass
                ),
                null
            );
        }

        ISmokeTestScenario scenario = (ISmokeTestScenario) rawInstance;

        // ── Build effective budget (CMT overrides win over scenario defaults) ─
        GovernorBudgetConfig effectiveBudget = buildEffectiveBudget(config, scenario.getGovernorBudget());

        // ── Execution with tracking ────────────────────────────────────────────
        GovernorLimitBudget    tracker = new GovernorLimitBudget();
        ScenarioTimeoutHandler timer   = new ScenarioTimeoutHandler();

        tracker.captureBaseline();
        timer.startTimer();

        Long startMs = System.currentTimeMillis();
        ScenarioResult result;

        try {
            result = scenario.execute(context);
            // Post-execution cooperative timeout check
            timer.checkAndThrow(effectiveBudget.timeoutSeconds);
        } catch (ScenarioTimeoutException e) {
            Long elapsed = System.currentTimeMillis() - startMs;
            result = ScenarioResult.failure(
                config.scenarioName, elapsed, 'TIMED_OUT',
                cap(e.getMessage(), 1000)
            );
        } catch (DmlException e) {
            Long elapsed = System.currentTimeMillis() - startMs;
            result = ScenarioResult.failure(
                config.scenarioName, elapsed, 'DML_EXCEPTION',
                cap(ErrorSanitizer.sanitize(e.getMessage()), 1000)
            );
        } catch (QueryException e) {
            Long elapsed = System.currentTimeMillis() - startMs;
            result = ScenarioResult.failure(
                config.scenarioName, elapsed, 'QUERY_EXCEPTION',
                cap(ErrorSanitizer.sanitize(e.getMessage()), 1000)
            );
        } catch (Exception e) {
            Long elapsed = System.currentTimeMillis() - startMs;
            result = ScenarioResult.failure(
                config.scenarioName, elapsed, 'UNEXPECTED_ERROR',
                cap(ErrorSanitizer.sanitize(e.getMessage()), 1000)
            );
        }

        GovernorConsumptionReport report = tracker.getConsumptionReport(effectiveBudget);
        return new DispatchResult(result, report);
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private GovernorBudgetConfig buildEffectiveBudget(ScenarioConfig config, GovernorBudgetConfig scenarioBudget) {
        Integer cpu     = config.governorBudgetOverrideCPU  != null ? config.governorBudgetOverrideCPU  : scenarioBudget.cpuBudgetMs;
        Integer soql    = config.governorBudgetOverrideSOQL != null ? config.governorBudgetOverrideSOQL : scenarioBudget.soqlBudget;
        Integer dml     = config.governorBudgetOverrideDML  != null ? config.governorBudgetOverrideDML  : scenarioBudget.dmlBudget;
        Integer timeout = config.timeoutOverrideSec         != null ? config.timeoutOverrideSec         : scenarioBudget.timeoutSeconds;
        return new GovernorBudgetConfig(cpu, soql, dml, timeout);
    }

    private static String cap(String value, Integer maxLen) {
        if (value == null) { return null; }
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }
}
