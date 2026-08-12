global interface ISmokeTestScenario {
    ScenarioResult       execute(SmokeTestContext context);
    ScenarioMetadata     getMetadata();
    GovernorBudgetConfig getGovernorBudget();
}
