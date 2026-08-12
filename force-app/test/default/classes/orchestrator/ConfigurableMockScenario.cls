/**
 * Configurable no-arg-constructor test mock for ScenarioDispatcher tests.
 *
 * Behaviour is controlled via @TestVisible static fields, which must be reset in
 * finally blocks to prevent cross-test pollution. A no-arg constructor is required
 * so Type.forName('ConfigurableMockScenario').newInstance() succeeds in test context.
 */
@isTest
global class ConfigurableMockScenario implements ISmokeTestScenario {

    @TestVisible static Boolean shouldPass              = true;
    @TestVisible static Boolean shouldThrowDmlException   = false;
    @TestVisible static Boolean shouldThrowQueryException = false;
    @TestVisible static Boolean shouldThrowException      = false;
    @TestVisible static String  injectedErrorType         = 'ASSERTION_FAILURE';
    @TestVisible static String  injectedErrorDetail       = 'Configurable mock scenario failure';

    global ConfigurableMockScenario() { }

    global ScenarioResult execute(SmokeTestContext context) {
        if (shouldThrowDmlException) {
            DmlException e = new DmlException();
            e.setMessage('Mock DML exception from ConfigurableMockScenario');
            throw e;
        }
        if (shouldThrowQueryException) {
            QueryException e = new QueryException();
            e.setMessage('Mock query exception from ConfigurableMockScenario');
            throw e;
        }
        if (shouldThrowException) {
            throw new IllegalArgumentException('Mock unhandled exception from ConfigurableMockScenario');
        }
        if (shouldPass) {
            return ScenarioResult.success('ConfigurableMockScenario', 100L);
        }
        return ScenarioResult.failure(
            'ConfigurableMockScenario', 100L,
            injectedErrorType  != null ? injectedErrorType  : 'ASSERTION_FAILURE',
            injectedErrorDetail != null ? injectedErrorDetail : 'Mock failure'
        );
    }

    global ScenarioMetadata getMetadata() {
        return new ScenarioMetadata('ConfigurableMockScenario', 'Configurable test mock', false, null, 1);
    }

    global GovernorBudgetConfig getGovernorBudget() {
        return new GovernorBudgetConfig();
    }

    global static void reset() {
        shouldPass              = true;
        shouldThrowDmlException   = false;
        shouldThrowQueryException = false;
        shouldThrowException      = false;
        injectedErrorType         = 'ASSERTION_FAILURE';
        injectedErrorDetail       = 'Configurable mock scenario failure';
    }
}
