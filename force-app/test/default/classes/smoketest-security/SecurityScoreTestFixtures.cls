/**
 * Pre-built SecurityHealthCheckResult fixtures for comparator unit tests.
 *
 * All factory methods return complete, valid results unless the name indicates
 * otherwise (e.g., errorResult, skippedResult).
 */
@isTest
public class SecurityScoreTestFixtures {

    // =========================================================================
    // Simple score fixtures (no risk categories)
    // =========================================================================

    /** Post-deployment score well above typical thresholds (score=95) */
    public static SecurityHealthCheckResult highScore() {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore    = 95;
        r.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.PASS;
        return r;
    }

    /** Score exactly at the default absolute threshold (score=80) — boundary pass */
    public static SecurityHealthCheckResult atThreshold() {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore    = 80;
        r.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.PASS;
        return r;
    }

    /** Score one point below the default absolute threshold (score=79) */
    public static SecurityHealthCheckResult oneBelowThreshold() {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore    = 79;
        r.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.FAIL;
        return r;
    }

    /** Score clearly below threshold (score=60) */
    public static SecurityHealthCheckResult lowScore() {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore    = 60;
        r.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.FAIL;
        return r;
    }

    /** Score = 0 (minimum possible) */
    public static SecurityHealthCheckResult zeroScore() {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore    = 0;
        r.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.FAIL;
        return r;
    }

    /** Pre-deployment baseline for boundary delta tests (score=85) */
    public static SecurityHealthCheckResult preBaseline85() {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore    = 85;
        r.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.PASS;
        return r;
    }

    /** Post-deployment score exactly at max drop from 85 baseline (drop=5 → score=80) */
    public static SecurityHealthCheckResult atMaxDrop() {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore    = 80;
        r.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.PASS;
        return r;
    }

    /** Post-deployment score one point beyond max drop from 85 baseline (drop=6 → score=79) */
    public static SecurityHealthCheckResult oneOverMaxDrop() {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore    = 79;
        r.thresholdStatus = SecurityHealthCheckResult.ThresholdStatus.FAIL;
        return r;
    }

    // =========================================================================
    // Error / skipped fixtures
    // =========================================================================

    public static SecurityHealthCheckResult errorResult() {
        return SecurityHealthCheckResult.error('Tooling API callout failed: HTTP 500');
    }

    public static SecurityHealthCheckResult skippedResult() {
        return SecurityHealthCheckResult.skipped('API call budget exhausted');
    }

    // =========================================================================
    // Fixtures with risk categories for category-diff tests
    // =========================================================================

    /** Pre-deployment result with two risk categories */
    public static SecurityHealthCheckResult withCategories(Integer score, List<String> categoryNames, List<Integer> scores) {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore    = score;
        r.thresholdStatus = score >= 80
            ? SecurityHealthCheckResult.ThresholdStatus.PASS
            : SecurityHealthCheckResult.ThresholdStatus.FAIL;
        r.riskCategories  = new List<SecurityHealthCheckResult.SecurityRiskCategory>();
        for (Integer i = 0; i < categoryNames.size(); i++) {
            SecurityHealthCheckResult.SecurityRiskCategory cat =
                new SecurityHealthCheckResult.SecurityRiskCategory();
            cat.categoryName = categoryNames[i];
            cat.score        = (scores != null && i < scores.size()) ? scores[i] : 0;
            r.riskCategories.add(cat);
        }
        return r;
    }
}
