@isTest
private class SecurityScoreComparatorTest {

    // =========================================================================
    // Scenario 1: Both scores above threshold, small delta → Pass, None
    // =========================================================================
    @isTest
    static void compare_bothAboveThresholdSmallDelta_returnsPass() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        SecurityHealthCheckResult pre  = SecurityScoreTestFixtures.highScore();   // 95
        SecurityHealthCheckResult post = SecurityScoreTestFixtures.highScore();   // 95

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(pre, post);
        Test.stopTest();

        System.assertEquals(SecurityComparisonResult.Status.Pass, result.status,
            'Both scores identical and above threshold — should Pass');
        System.assertEquals(SecurityComparisonResult.ViolationType.None, result.violationType,
            'No violation expected when both thresholds are met');
        System.assertEquals(95, result.preScore);
        System.assertEquals(95, result.postScore);
        System.assertEquals(0,  result.scoreDelta);
    }

    // =========================================================================
    // Scenario 2: Post-score exactly at absolute threshold boundary → Pass
    // =========================================================================
    @isTest
    static void compare_postScoreAtThresholdBoundary_returnsPass() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        SecurityHealthCheckResult pre  = SecurityScoreTestFixtures.preBaseline85();  // 85
        SecurityHealthCheckResult post = SecurityScoreTestFixtures.atThreshold();    // 80 = threshold

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(pre, post);
        Test.stopTest();

        System.assertEquals(SecurityComparisonResult.Status.Pass, result.status,
            'Post score equal to absolute threshold should Pass (boundary-inclusive)');
        System.assertEquals(SecurityComparisonResult.ViolationType.None, result.violationType);
        System.assertEquals(80, result.postScore);
    }

    // =========================================================================
    // Scenario 3: Post-score one point below threshold → Fail, Absolute
    // =========================================================================
    @isTest
    static void compare_postScoreOneBelowThreshold_returnsAbsoluteFail() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        SecurityHealthCheckResult pre  = SecurityScoreTestFixtures.preBaseline85();    // 85
        SecurityHealthCheckResult post = SecurityScoreTestFixtures.oneBelowThreshold(); // 79

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(pre, post);
        Test.stopTest();

        System.assertEquals(SecurityComparisonResult.Status.Fail, result.status,
            'Post score 79 < threshold 80 — should Fail');
        System.assertEquals(SecurityComparisonResult.ViolationType.Absolute, result.violationType,
            'Only absolute threshold is violated');
        System.assertEquals(79, result.postScore);
        System.assertEquals(6,  result.scoreDelta, 'Delta = 85 - 79 = 6');
        System.assertNotEquals(null, result.detailMessage);
    }

    // =========================================================================
    // Scenario 4: Delta exactly at max drop boundary → Pass
    // =========================================================================
    @isTest
    static void compare_deltaAtMaxDropBoundary_returnsPass() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        // pre=85, post=80 → delta=5 = maxDrop; absolute threshold: 80 >= 80 → Pass
        SecurityHealthCheckResult pre  = SecurityScoreTestFixtures.preBaseline85(); // 85
        SecurityHealthCheckResult post = SecurityScoreTestFixtures.atMaxDrop();     // 80

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(pre, post);
        Test.stopTest();

        System.assertEquals(SecurityComparisonResult.Status.Pass, result.status,
            'Delta equal to maxDrop should Pass (boundary-inclusive)');
        System.assertEquals(SecurityComparisonResult.ViolationType.None, result.violationType);
        System.assertEquals(5, result.scoreDelta, 'Delta = 85 - 80 = 5');
    }

    // =========================================================================
    // Scenario 5: Delta one point above max drop → Fail, Delta
    // =========================================================================
    @isTest
    static void compare_deltaOneOverMaxDrop_returnsDeltaFail() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        // pre=85, post=79 → delta=6 > maxDrop=5
        // absolute: post=79 < threshold=80 → also fails absolute
        // Use pre=90 so absolute doesn't fail (post=84, delta=6 > 5)
        SecurityHealthCheckResult pre = new SecurityHealthCheckResult();
        pre.overallScore    = 90;
        pre.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.PASS;

        SecurityHealthCheckResult post = new SecurityHealthCheckResult();
        post.overallScore    = 84;  // above threshold=80, delta=6 > maxDrop=5
        post.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.PASS;

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(pre, post);
        Test.stopTest();

        System.assertEquals(SecurityComparisonResult.Status.Fail, result.status,
            'Delta 6 > maxDrop 5 — should Fail');
        System.assertEquals(SecurityComparisonResult.ViolationType.Delta, result.violationType,
            'Only delta threshold is violated');
        System.assertEquals(6, result.scoreDelta, 'Delta = 90 - 84 = 6');
        System.assertEquals(84, result.postScore);
    }

    // =========================================================================
    // Scenario 6: Both thresholds violated → Fail, Both
    // =========================================================================
    @isTest
    static void compare_bothThresholdsViolated_returnsBothFail() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        // pre=90, post=70 → delta=20 > maxDrop=5, post=70 < threshold=80
        SecurityHealthCheckResult pre = new SecurityHealthCheckResult();
        pre.overallScore    = 90;
        pre.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.PASS;

        SecurityHealthCheckResult post = new SecurityHealthCheckResult();
        post.overallScore    = 70;
        post.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.FAIL;

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(pre, post);
        Test.stopTest();

        System.assertEquals(SecurityComparisonResult.Status.Fail, result.status);
        System.assertEquals(SecurityComparisonResult.ViolationType.Both, result.violationType,
            'Both absolute and delta thresholds violated');
        System.assertEquals(20, result.scoreDelta, 'Delta = 90 - 70 = 20');
        System.assertEquals(70, result.postScore);
        System.assertNotEquals(null, result.detailMessage);
        System.assertEquals(80, result.configuredThreshold);
        System.assertEquals(5,  result.configuredMaxDrop);
    }

    // =========================================================================
    // Scenario 7a: Pre-result is null → Error
    // =========================================================================
    @isTest
    static void compare_nullPreResult_returnsError() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(null, SecurityScoreTestFixtures.highScore());
        Test.stopTest();

        System.assertEquals(SecurityComparisonResult.Status.Error, result.status,
            'Null pre-result should produce Error status');
        System.assertEquals(SecurityComparisonResult.ViolationType.None, result.violationType);
        System.assertNotEquals(null, result.detailMessage);
        System.assertEquals(null, result.preScore);
        System.assertEquals(null, result.postScore);
    }

    // =========================================================================
    // Scenario 7b: Post-result has ERROR status → Error
    // =========================================================================
    @isTest
    static void compare_postResultErrorStatus_returnsError() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        SecurityHealthCheckResult pre  = SecurityScoreTestFixtures.highScore();
        SecurityHealthCheckResult post = SecurityScoreTestFixtures.errorResult();

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(pre, post);
        Test.stopTest();

        System.assertEquals(SecurityComparisonResult.Status.Error, result.status,
            'Post-result with ERROR status should propagate as Error');
        System.assertEquals(SecurityComparisonResult.ViolationType.None, result.violationType);
        System.assertNotEquals(null, result.detailMessage);
    }

    // =========================================================================
    // Scenario 7c: Pre-result has SKIPPED status → Error
    // =========================================================================
    @isTest
    static void compare_preResultSkippedStatus_returnsError() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        SecurityHealthCheckResult pre  = SecurityScoreTestFixtures.skippedResult();
        SecurityHealthCheckResult post = SecurityScoreTestFixtures.highScore();

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(pre, post);
        Test.stopTest();

        System.assertEquals(SecurityComparisonResult.Status.Error, result.status,
            'Pre-result with SKIPPED status should produce Error');
    }

    // =========================================================================
    // Scenario 8: Category diff — changed categories detected
    // =========================================================================
    @isTest
    static void compare_changedRiskCategories_populatesChangedList() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        // Pre: categories A(score=90), B(score=85)
        SecurityHealthCheckResult pre = SecurityScoreTestFixtures.withCategories(
            88,
            new List<String>{ 'CategoryA', 'CategoryB' },
            new List<Integer>{ 90, 85 }
        );

        // Post: CategoryA unchanged (90), CategoryB dropped (70), CategoryC new
        SecurityHealthCheckResult post = SecurityScoreTestFixtures.withCategories(
            85,
            new List<String>{ 'CategoryA', 'CategoryB', 'CategoryC' },
            new List<Integer>{ 90, 70, 60 }
        );

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(pre, post);
        Test.stopTest();

        System.assertNotEquals(null, result.changedCategories);
        // CategoryB changed (85→70), CategoryC is new → both flagged
        System.assertEquals(2, result.changedCategories.size(),
            'CategoryB (score change) and CategoryC (new) should be flagged');
        System.assert(result.changedCategories.contains('CategoryB'), 'CategoryB score changed');
        System.assert(result.changedCategories.contains('CategoryC'), 'CategoryC is new');
        System.assert(!result.changedCategories.contains('CategoryA'), 'CategoryA unchanged');
    }

    // =========================================================================
    // Scenario 9: No risk categories on either result → empty changed list
    // =========================================================================
    @isTest
    static void compare_noRiskCategories_changedListEmpty() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        SecurityHealthCheckResult pre  = SecurityScoreTestFixtures.highScore(); // no categories
        SecurityHealthCheckResult post = SecurityScoreTestFixtures.highScore();

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(pre, post);
        Test.stopTest();

        System.assertNotEquals(null, result.changedCategories);
        System.assertEquals(0, result.changedCategories.size(),
            'No categories to compare — changed list should be empty');
    }

    // =========================================================================
    // Scenario: Result fields are fully populated on a Pass
    // =========================================================================
    @isTest
    static void compare_passResult_allFieldsPopulated() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        SecurityHealthCheckResult pre  = SecurityScoreTestFixtures.preBaseline85(); // 85
        SecurityHealthCheckResult post = SecurityScoreTestFixtures.highScore();     // 95 (improved)

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(pre, post);
        Test.stopTest();

        System.assertEquals(SecurityComparisonResult.Status.Pass, result.status);
        System.assertEquals(85, result.preScore);
        System.assertEquals(95, result.postScore);
        System.assertEquals(-10, result.scoreDelta, 'Score improved by 10 — negative delta');
        System.assertEquals(80, result.configuredThreshold);
        System.assertEquals(5,  result.configuredMaxDrop);
        System.assertNotEquals(null, result.detailMessage);
    }

    // =========================================================================
    // Scenario: Null post-result → Error
    // =========================================================================
    @isTest
    static void compare_nullPostResult_returnsError() {
        SecurityScoreComparator comparator = new SecurityScoreComparator();

        Test.startTest();
        SecurityComparisonResult result = comparator.compare(SecurityScoreTestFixtures.highScore(), null);
        Test.stopTest();

        System.assertEquals(SecurityComparisonResult.Status.Error, result.status,
            'Null post-result should produce Error status');
        System.assertEquals(SecurityComparisonResult.ViolationType.None, result.violationType);
        System.assertNotEquals(null, result.detailMessage);
    }
}
