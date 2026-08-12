/**
 * Unit tests for GovernorLimitBudget and GovernorConsumptionReport.
 *
 * Test categories:
 *   Baseline capture     — captureBaseline() records current Limits values
 *   SOQL tracking        — soqlUsed equals queries performed after baseline
 *   DML tracking         — dmlUsed equals DML statements performed after baseline
 *   Combined tracking    — both soqlUsed=3 and dmlUsed=2 verified together
 *   CPU tracking         — cpuUsed is non-negative, budget matches config
 *   isWithinBudget true  — returns true when under all three budgets
 *   isWithinBudget false — returns false when any dimension exceeds budget
 *   Boundary inclusive   — exact boundary (used == budget) is within budget
 *   Zero consumption     — zero ops after baseline is within any positive budget
 *   Repeated baseline    — second captureBaseline() resets the counter
 *   IllegalState guards  — isWithinBudget and getConsumptionReport throw before baseline
 *   Report direct ctor   — GovernorConsumptionReport exceeded flags verified directly
 *   Report field values  — all 9 fields populated correctly by constructor
 */
@isTest
private class GovernorLimitBudgetTest {

    private static GovernorBudgetConfig defaultConfig() {
        return new GovernorBudgetConfig(5000, 50, 50, 30);
    }

    // =========================================================================
    // SOQL consumption tracking
    // =========================================================================

    @isTest
    static void testSoqlConsumptionTrackedAfterBaseline() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        tracker.captureBaseline();

        List<Account> r1 = [SELECT Id FROM Account LIMIT 1];
        List<Account> r2 = [SELECT Id FROM Account LIMIT 1];
        List<Account> r3 = [SELECT Id FROM Account LIMIT 1];

        GovernorConsumptionReport report = tracker.getConsumptionReport(defaultConfig());

        System.assertEquals(3, report.soqlUsed,
            'SOQL consumption must be exactly 3 after 3 queries');
        System.assertEquals(50, report.soqlBudget,
            'SOQL budget must equal config.soqlBudget');
        System.assertFalse(report.soqlExceeded,
            'SOQL must not be exceeded with budget 50 and usage 3');
    }

    // =========================================================================
    // DML consumption tracking
    // =========================================================================

    @isTest
    static void testDmlConsumptionTrackedAfterBaseline() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        tracker.captureBaseline();

        insert new Account(Name = 'SMOKE_TEST Gov DML 001');
        insert new Account(Name = 'SMOKE_TEST Gov DML 002');

        GovernorConsumptionReport report = tracker.getConsumptionReport(defaultConfig());

        System.assertEquals(2, report.dmlUsed,
            'DML consumption must be exactly 2 after 2 insert statements');
        System.assertEquals(50, report.dmlBudget,
            'DML budget must equal config.dmlBudget');
        System.assertFalse(report.dmlExceeded,
            'DML must not be exceeded with budget 50 and usage 2');
    }

    // =========================================================================
    // Combined SOQL + DML (canonical acceptance criterion test)
    // =========================================================================

    @isTest
    static void testCombinedSoqlAndDmlConsumption() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        tracker.captureBaseline();

        // Exactly 3 SOQL queries
        List<Account> r1 = [SELECT Id FROM Account LIMIT 1];
        List<Account> r2 = [SELECT Id FROM Account LIMIT 1];
        List<Account> r3 = [SELECT Id FROM Account LIMIT 1];

        // Exactly 2 DML statements
        insert new Account(Name = 'SMOKE_TEST Gov Combo 001');
        insert new Account(Name = 'SMOKE_TEST Gov Combo 002');

        GovernorConsumptionReport report = tracker.getConsumptionReport(defaultConfig());

        System.assertEquals(3, report.soqlUsed, 'Combined: soqlUsed must be 3');
        System.assertEquals(2, report.dmlUsed,  'Combined: dmlUsed must be 2');
    }

    // =========================================================================
    // CPU consumption tracking
    // =========================================================================

    @isTest
    static void testCpuConsumptionIsNonNegativeAndBudgetSet() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        tracker.captureBaseline();

        Integer x = 0;
        for (Integer i = 0; i < 10000; i++) {
            x += i;
        }

        GovernorConsumptionReport report = tracker.getConsumptionReport(defaultConfig());

        System.assert(report.cpuUsed >= 0,
            'CPU usage must be a non-negative value');
        System.assertEquals(5000, report.cpuBudget,
            'CPU budget must match GovernorBudgetConfig.cpuBudgetMs');
    }

    // =========================================================================
    // isWithinBudget — true cases
    // =========================================================================

    @isTest
    static void testIsWithinBudgetReturnsTrueUnderAllLimits() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        tracker.captureBaseline();

        List<Account> r1 = [SELECT Id FROM Account LIMIT 1];
        insert new Account(Name = 'SMOKE_TEST Gov Within 001');

        System.assertTrue(tracker.isWithinBudget(defaultConfig()),
            'Must return true when consumption is well under 50/50/5000');
    }

    @isTest
    static void testIsWithinBudgetTrueWithZeroConsumption() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        tracker.captureBaseline();

        GovernorBudgetConfig minConfig = new GovernorBudgetConfig(100, 1, 1, 1);
        System.assertTrue(tracker.isWithinBudget(minConfig),
            'Zero consumption must be within any positive budget');
    }

    // =========================================================================
    // isWithinBudget — false cases
    // =========================================================================

    @isTest
    static void testIsWithinBudgetFalseWhenSoqlExceeded() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        tracker.captureBaseline();

        List<Account> r1 = [SELECT Id FROM Account LIMIT 1];
        List<Account> r2 = [SELECT Id FROM Account LIMIT 1];
        List<Account> r3 = [SELECT Id FROM Account LIMIT 1];

        GovernorBudgetConfig tightSoql = new GovernorBudgetConfig(5000, 2, 50, 30);
        System.assertFalse(tracker.isWithinBudget(tightSoql),
            'Must return false when SOQL consumption (3) exceeds budget (2)');
    }

    @isTest
    static void testIsWithinBudgetFalseWhenDmlExceeded() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        tracker.captureBaseline();

        insert new Account(Name = 'SMOKE_TEST Gov DmlEx 001');
        insert new Account(Name = 'SMOKE_TEST Gov DmlEx 002');
        insert new Account(Name = 'SMOKE_TEST Gov DmlEx 003');

        GovernorBudgetConfig tightDml = new GovernorBudgetConfig(5000, 50, 2, 30);
        System.assertFalse(tracker.isWithinBudget(tightDml),
            'Must return false when DML consumption (3) exceeds budget (2)');
    }

    @isTest
    static void testIsWithinBudgetFalseWithTightBudgetOf2And2() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        tracker.captureBaseline();

        List<Account> r1 = [SELECT Id FROM Account LIMIT 1];
        List<Account> r2 = [SELECT Id FROM Account LIMIT 1];
        List<Account> r3 = [SELECT Id FROM Account LIMIT 1];
        insert new Account(Name = 'SMOKE_TEST Gov Tight 001');
        insert new Account(Name = 'SMOKE_TEST Gov Tight 002');
        insert new Account(Name = 'SMOKE_TEST Gov Tight 003');

        GovernorBudgetConfig tightConfig = new GovernorBudgetConfig(100, 2, 2, 30);
        System.assertFalse(tracker.isWithinBudget(tightConfig),
            'Must return false when both SOQL (3) and DML (3) exceed budget (2)');
    }

    // =========================================================================
    // Boundary inclusive (used == budget)
    // =========================================================================

    @isTest
    static void testBudgetAtExactBoundaryIsWithinBudget() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        tracker.captureBaseline();

        List<Account> r1 = [SELECT Id FROM Account LIMIT 1];
        List<Account> r2 = [SELECT Id FROM Account LIMIT 1];
        List<Account> r3 = [SELECT Id FROM Account LIMIT 1];

        // Budget equals consumption — should be within budget (<=)
        GovernorBudgetConfig exactConfig = new GovernorBudgetConfig(5000, 3, 50, 30);
        System.assertTrue(tracker.isWithinBudget(exactConfig),
            'Exact boundary (used == budget) must be within budget (inclusive <=)');
    }

    // =========================================================================
    // Repeated baseline capture
    // =========================================================================

    @isTest
    static void testRepeatedBaselineCaptureOverwritesPrevious() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        tracker.captureBaseline();

        // Consume 2 SOQL queries before second capture
        List<Account> r1 = [SELECT Id FROM Account LIMIT 1];
        List<Account> r2 = [SELECT Id FROM Account LIMIT 1];

        // Re-capture — baseline now set to current Limits values (includes those 2 queries)
        tracker.captureBaseline();

        // No further operations — consumption since second baseline should be 0
        GovernorConsumptionReport report = tracker.getConsumptionReport(defaultConfig());

        System.assertEquals(0, report.soqlUsed,
            'After re-capturing baseline, soqlUsed must be 0 (previous queries baked into new baseline)');
        System.assertEquals(0, report.dmlUsed,
            'After re-capturing baseline, dmlUsed must be 0');
    }

    // =========================================================================
    // IllegalStateException guards
    // =========================================================================

    @isTest
    static void testIsWithinBudgetBeforeBaselineThrows() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        IllegalStateException thrown;
        try {
            tracker.isWithinBudget(defaultConfig());
        } catch (IllegalStateException e) {
            thrown = e;
        }
        System.assertNotEquals(null, thrown,
            'Must throw IllegalStateException when isWithinBudget called before captureBaseline');
        System.assert(thrown.getMessage().contains('captureBaseline'),
            'Exception message must mention captureBaseline');
        System.assert(thrown.getMessage().contains('isWithinBudget'),
            'Exception message must identify the calling method');
    }

    @isTest
    static void testGetConsumptionReportBeforeBaselineThrows() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        IllegalStateException thrown;
        try {
            tracker.getConsumptionReport(defaultConfig());
        } catch (IllegalStateException e) {
            thrown = e;
        }
        System.assertNotEquals(null, thrown,
            'Must throw IllegalStateException when getConsumptionReport called before captureBaseline');
        System.assert(thrown.getMessage().contains('captureBaseline'),
            'Exception message must mention captureBaseline');
        System.assert(thrown.getMessage().contains('getConsumptionReport'),
            'Exception message must identify the calling method');
    }

    // =========================================================================
    // GovernorConsumptionReport constructor and exceeded flag calculations
    // =========================================================================

    @isTest
    static void testReportExceededFlagsWhenSoqlOver() {
        GovernorConsumptionReport report = new GovernorConsumptionReport(5, 1, 100, 3, 50, 5000);
        System.assertTrue(report.soqlExceeded,  'soqlExceeded must be true when used(5) > budget(3)');
        System.assertFalse(report.dmlExceeded,   'dmlExceeded must be false when used(1) <= budget(50)');
        System.assertFalse(report.cpuExceeded,   'cpuExceeded must be false when used(100) <= budget(5000)');
    }

    @isTest
    static void testReportExceededFlagsWhenAllOver() {
        GovernorConsumptionReport report = new GovernorConsumptionReport(10, 10, 6000, 5, 5, 5000);
        System.assertTrue(report.soqlExceeded);
        System.assertTrue(report.dmlExceeded);
        System.assertTrue(report.cpuExceeded);
    }

    @isTest
    static void testReportExceededFlagsWhenNoneOver() {
        GovernorConsumptionReport report = new GovernorConsumptionReport(3, 3, 100, 50, 50, 5000);
        System.assertFalse(report.soqlExceeded);
        System.assertFalse(report.dmlExceeded);
        System.assertFalse(report.cpuExceeded);
    }

    @isTest
    static void testReportExceededFlagsAtExactBoundaryNotExceeded() {
        // used == budget is NOT exceeded (strict >)
        GovernorConsumptionReport report = new GovernorConsumptionReport(50, 50, 5000, 50, 50, 5000);
        System.assertFalse(report.soqlExceeded, 'Exact boundary must NOT be exceeded');
        System.assertFalse(report.dmlExceeded,  'Exact boundary must NOT be exceeded');
        System.assertFalse(report.cpuExceeded,  'Exact boundary must NOT be exceeded');
    }

    @isTest
    static void testReportFieldsArePopulatedCorrectly() {
        GovernorConsumptionReport report = new GovernorConsumptionReport(3, 2, 150, 50, 40, 4000);
        System.assertEquals(3,    report.soqlUsed);
        System.assertEquals(2,    report.dmlUsed);
        System.assertEquals(150,  report.cpuUsed);
        System.assertEquals(50,   report.soqlBudget);
        System.assertEquals(40,   report.dmlBudget);
        System.assertEquals(4000, report.cpuBudget);
    }

    @isTest
    static void testReportFromGetConsumptionReportHasCorrectBudgets() {
        GovernorLimitBudget tracker = new GovernorLimitBudget();
        tracker.captureBaseline();

        GovernorBudgetConfig config = new GovernorBudgetConfig(3000, 25, 15, 60);
        GovernorConsumptionReport report = tracker.getConsumptionReport(config);

        System.assertEquals(25,   report.soqlBudget, 'soqlBudget must match config.soqlBudget');
        System.assertEquals(15,   report.dmlBudget,  'dmlBudget must match config.dmlBudget');
        System.assertEquals(3000, report.cpuBudget,  'cpuBudget must match config.cpuBudgetMs');
    }
}
