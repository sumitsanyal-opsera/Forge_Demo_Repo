global with sharing class GovernorBudgetConfig {

    global final Integer cpuBudgetMs;
    global final Integer soqlBudget;
    global final Integer dmlBudget;
    global final Integer timeoutSeconds;

    global GovernorBudgetConfig() {
        this(5000, 50, 50, 30);
    }

    global GovernorBudgetConfig(
        Integer cpuBudgetMs,
        Integer soqlBudget,
        Integer dmlBudget,
        Integer timeoutSeconds
    ) {
        if (cpuBudgetMs == null || cpuBudgetMs < 100) {
            throw new IllegalArgumentException(
                'cpuBudgetMs must be >= 100; received: ' + cpuBudgetMs);
        }
        if (soqlBudget == null || soqlBudget < 1) {
            throw new IllegalArgumentException(
                'soqlBudget must be >= 1; received: ' + soqlBudget);
        }
        if (dmlBudget == null || dmlBudget < 1) {
            throw new IllegalArgumentException(
                'dmlBudget must be >= 1; received: ' + dmlBudget);
        }
        if (timeoutSeconds == null || timeoutSeconds < 1) {
            throw new IllegalArgumentException(
                'timeoutSeconds must be >= 1; received: ' + timeoutSeconds);
        }
        this.cpuBudgetMs    = cpuBudgetMs;
        this.soqlBudget     = soqlBudget;
        this.dmlBudget      = dmlBudget;
        this.timeoutSeconds = timeoutSeconds;
    }
}
