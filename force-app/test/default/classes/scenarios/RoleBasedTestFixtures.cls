/**
 * Test fixture factory for role-based scenario execution tests.
 *
 * Provides:
 *   - Test user creation methods for System Administrator, Standard User, and a
 *     configurable custom profile (Minimum Access - Salesforce as the third MVP profile)
 *   - Mock ISmokeTestScenario implementations that simulate success and permission failure
 *   - SmokeTestExecution__c factory for providing valid SmokeTestContext instances
 *
 * All test users are created within the test transaction and automatically rolled back —
 * no persistent user records are created in the org.
 */
@isTest
public class RoleBasedTestFixtures {

    // Standard MVP profile names
    public static final String PROFILE_SYS_ADMIN     = 'System Administrator';
    public static final String PROFILE_STANDARD_USER = 'Standard User';
    public static final String PROFILE_MIN_ACCESS     = 'Minimum Access - Salesforce';

    // =========================================================================
    // Test user factories — wraps SmokeTestDataFactory for convenience
    // =========================================================================

    /** Creates and inserts a test user with the System Administrator profile */
    public static User createSysAdminUser() {
        return SmokeTestDataFactory.createUserWithProfile(PROFILE_SYS_ADMIN);
    }

    /** Creates and inserts a test user with the Standard User profile */
    public static User createStandardUser() {
        return SmokeTestDataFactory.createUserWithProfile(PROFILE_STANDARD_USER);
    }

    /**
     * Creates and inserts a test user with the third MVP profile.
     * Uses 'Minimum Access - Salesforce' as the configurable custom profile.
     * Callers can pass any valid Profile Name supported by the org.
     */
    public static User createCustomProfileUser(String profileName) {
        return SmokeTestDataFactory.createUserWithProfile(
            (String.isNotBlank(profileName)) ? profileName : PROFILE_MIN_ACCESS
        );
    }

    /** Creates and inserts a test user with the minimum-access profile */
    public static User createMinAccessUser() {
        return SmokeTestDataFactory.createUserWithProfile(PROFILE_MIN_ACCESS);
    }

    // =========================================================================
    // SmokeTestExecution__c factory
    // =========================================================================

    public static SmokeTestExecution__c makeExecution() {
        SmokeTestExecution__c exec = new SmokeTestExecution__c(
            Status__c         = 'In Progress',
            TriggerSource__c  = 'Role-Based Test',
            StartTime__c      = DateTime.now(),
            TotalScenarios__c = 1
        );
        insert exec;
        return exec;
    }

    public static SmokeTestContext makeContext() {
        SmokeTestExecution__c exec = makeExecution();
        return new SmokeTestContext(exec.Id, null, new Map<String, Object>());
    }

    // =========================================================================
    // Mock scenario implementations
    // =========================================================================

    /**
     * Mock scenario that always succeeds — simulates an AccountCrudScenario
     * passing under the given profile.
     */
    public class AlwaysPassScenario implements ISmokeTestScenario {
        private String name;
        public AlwaysPassScenario(String scenarioName) { this.name = scenarioName; }

        public ScenarioResult execute(SmokeTestContext context) {
            return ScenarioResult.success(name, 100L);
        }

        public ScenarioMetadata getMetadata() {
            return new ScenarioMetadata(name, 'Always passes for fixture testing', false, 'Sales', 1);
        }

        public GovernorBudgetConfig getGovernorBudget() { return new GovernorBudgetConfig(); }
    }

    /**
     * Mock scenario that always throws a System.NoAccessException to simulate
     * FLS or CRUD permission failures under a restricted profile.
     */
    public class PermissionFailScenario implements ISmokeTestScenario {
        private String name;
        private String exceptionMessage;

        public PermissionFailScenario(String scenarioName, String exceptionMessage) {
            this.name             = scenarioName;
            this.exceptionMessage = exceptionMessage;
        }

        public ScenarioResult execute(SmokeTestContext context) {
            // Throw NoAccessException to simulate a permission failure
            // In tests, we throw DmlException with an access message since NoAccessException
            // cannot be directly instantiated from user code
            throw new System.NoAccessException();
        }

        public ScenarioMetadata getMetadata() {
            return new ScenarioMetadata(name, 'Simulates permission failure', false, 'Sales', 1);
        }

        public GovernorBudgetConfig getGovernorBudget() { return new GovernorBudgetConfig(); }
    }

    /**
     * Mock scenario that throws a non-permission exception (NullPointerException)
     * to verify that non-access errors are NOT classified as permission failures.
     */
    public class BusinessLogicFailScenario implements ISmokeTestScenario {
        private String name;
        public BusinessLogicFailScenario(String scenarioName) { this.name = scenarioName; }

        public ScenarioResult execute(SmokeTestContext context) {
            throw new NullPointerException();
        }

        public ScenarioMetadata getMetadata() {
            return new ScenarioMetadata(name, 'Simulates a non-permission business logic failure', false, 'Sales', 1);
        }

        public GovernorBudgetConfig getGovernorBudget() { return new GovernorBudgetConfig(); }
    }

    /**
     * Mock scenario that throws a DmlException with an access-related message.
     * Simulates an "insufficient access on cross reference entity" DML error.
     */
    public class DmlAccessFailScenario implements ISmokeTestScenario {
        private String name;
        public DmlAccessFailScenario(String scenarioName) { this.name = scenarioName; }

        public ScenarioResult execute(SmokeTestContext context) {
            // Simulate FLS DmlException by attempting to insert a record without permission
            // In unit tests, we use a constructed scenario result to avoid real DML failures
            return ScenarioResult.failure(name, 50L, 'DML_EXCEPTION',
                'insufficient access on cross reference entity for field Opportunity.Amount');
        }

        public ScenarioMetadata getMetadata() {
            return new ScenarioMetadata(name, 'Simulates DML access failure', false, 'Sales', 1);
        }

        public GovernorBudgetConfig getGovernorBudget() { return new GovernorBudgetConfig(); }
    }
}
