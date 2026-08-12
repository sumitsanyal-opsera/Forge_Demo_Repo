@isTest
global class MockSmokeTestScenario implements ISmokeTestScenario {

    private final ScenarioMetadata     metadata;
    private final GovernorBudgetConfig budget;
    private final Boolean              shouldPass;
    private final String               errorType;
    private final String               errorDetail;
    private final Long                 simulatedDurationMs;
    private final Boolean              simulateTimeout;

    global MockSmokeTestScenario(ScenarioMetadata metadata, Boolean shouldPass) {
        this(metadata, shouldPass, null, null, 100L, false);
    }

    global MockSmokeTestScenario(
        ScenarioMetadata metadata,
        Boolean          shouldPass,
        String           errorType,
        String           errorDetail
    ) {
        this(metadata, shouldPass, errorType, errorDetail, 100L, false);
    }

    global MockSmokeTestScenario(
        ScenarioMetadata metadata,
        Boolean          shouldPass,
        String           errorType,
        String           errorDetail,
        Long             simulatedDurationMs,
        Boolean          simulateTimeout
    ) {
        this.metadata            = metadata;
        this.budget              = new GovernorBudgetConfig();
        this.shouldPass          = shouldPass;
        this.errorType           = errorType;
        this.errorDetail         = errorDetail;
        this.simulatedDurationMs = (simulatedDurationMs != null) ? simulatedDurationMs : 100L;
        this.simulateTimeout     = (simulateTimeout     != null) ? simulateTimeout     : false;
    }

    global ScenarioResult execute(SmokeTestContext context) {
        if (simulateTimeout) {
            return ScenarioResult.failure(
                metadata.scenarioName,
                simulatedDurationMs,
                'TIMEOUT',
                'Scenario exceeded configured timeout budget'
            );
        }
        if (shouldPass) {
            return ScenarioResult.success(metadata.scenarioName, simulatedDurationMs);
        }
        return ScenarioResult.failure(
            metadata.scenarioName,
            simulatedDurationMs,
            (errorType   != null) ? errorType   : 'ASSERTION_FAILURE',
            (errorDetail != null) ? errorDetail : 'Mock scenario configured to fail'
        );
    }

    global ScenarioMetadata     getMetadata()       { return metadata; }
    global GovernorBudgetConfig getGovernorBudget() { return budget;   }
}
