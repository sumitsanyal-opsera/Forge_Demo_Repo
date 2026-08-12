/**
 * Evaluates pre-deployment and post-deployment security health scores against
 * configurable thresholds stored in SmokeTestConfig__mdt.
 *
 * Two threshold checks:
 *   Absolute — postScore must be >= SecurityScoreAbsoluteThreshold__c (default 80)
 *   Delta    — (preScore - postScore) must be <= SecurityScoreRelativeThreshold__c (default 5)
 *
 * Config is read via SmokeTestConfig__mdt.getAll() — zero SOQL cost.
 * Falls back to defaults (threshold=80, maxDrop=5) if no config record is found.
 */
public with sharing class SecurityScoreComparator {

    private static final Integer DEFAULT_THRESHOLD = 80;
    private static final Integer DEFAULT_MAX_DROP  = 5;
    private static final String  CONFIG_RECORD     = 'Default';

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Compares pre- and post-deployment SecurityHealthCheckResult objects against
     * configured thresholds.
     *
     * Returns SecurityComparisonResult.Status.Error when:
     *   - either input is null
     *   - preResult.thresholdStatus is ERROR or SKIPPED
     *   - postResult.thresholdStatus is ERROR or SKIPPED
     */
    public SecurityComparisonResult compare(
        SecurityHealthCheckResult preResult,
        SecurityHealthCheckResult postResult
    ) {
        // ── Input validation ──────────────────────────────────────────────────
        if (preResult == null) {
            return buildError(null, null,
                'Pre-deployment baseline unavailable — cannot compute delta');
        }
        if (postResult == null) {
            return buildError(preResult.overallScore, null,
                'Post-deployment result unavailable — comparison cannot be performed');
        }
        if (preResult.thresholdStatus == SecurityHealthCheckResult.ThresholdStatus.ERROR
            || preResult.thresholdStatus == SecurityHealthCheckResult.ThresholdStatus.SKIPPED) {
            return buildError(preResult.overallScore, postResult.overallScore,
                'Pre-deployment score has status '
                + preResult.thresholdStatus.name()
                + ' — cannot compute delta: '
                + (preResult.diagnosticMessage != null ? preResult.diagnosticMessage : ''));
        }
        if (postResult.thresholdStatus == SecurityHealthCheckResult.ThresholdStatus.ERROR
            || postResult.thresholdStatus == SecurityHealthCheckResult.ThresholdStatus.SKIPPED) {
            return buildError(preResult.overallScore, postResult.overallScore,
                'Post-deployment score has status '
                + postResult.thresholdStatus.name()
                + ' — comparison cannot be performed: '
                + (postResult.diagnosticMessage != null ? postResult.diagnosticMessage : ''));
        }

        // ── Load thresholds ────────────────────────────────────────────────────
        Integer threshold = DEFAULT_THRESHOLD;
        Integer maxDrop   = DEFAULT_MAX_DROP;

        Map<String, SmokeTestConfig__mdt> allConfigs = SmokeTestConfig__mdt.getAll();
        if (allConfigs != null && allConfigs.containsKey(CONFIG_RECORD)) {
            SmokeTestConfig__mdt cfg = allConfigs.get(CONFIG_RECORD);
            if (cfg.SecurityScoreAbsoluteThreshold__c != null) {
                threshold = Integer.valueOf(cfg.SecurityScoreAbsoluteThreshold__c);
            }
            if (cfg.SecurityScoreRelativeThreshold__c != null) {
                maxDrop = Integer.valueOf(cfg.SecurityScoreRelativeThreshold__c);
            }
        } else {
            System.debug(LoggingLevel.WARN,
                'SecurityScoreComparator: no Default SmokeTestConfig__mdt record found '
                + '— using defaults (threshold=' + DEFAULT_THRESHOLD
                + ', maxDrop=' + DEFAULT_MAX_DROP + ')');
        }

        // ── Score values ───────────────────────────────────────────────────────
        Integer pre   = preResult.overallScore  != null ? preResult.overallScore  : 0;
        Integer post  = postResult.overallScore != null ? postResult.overallScore : 0;
        Integer delta = pre - post; // positive = drop, negative = improvement

        // ── Threshold checks ───────────────────────────────────────────────────
        Boolean absoluteFail = post < threshold;
        Boolean deltaFail    = delta > maxDrop;   // strict: "dropped by MORE than maxDrop"

        // ── Category diff ──────────────────────────────────────────────────────
        List<String> changedCategories = computeChangedCategories(preResult, postResult);

        // ── Build result ───────────────────────────────────────────────────────
        SecurityComparisonResult result = new SecurityComparisonResult();
        result.preScore           = pre;
        result.postScore          = post;
        result.scoreDelta         = delta;
        result.configuredThreshold = threshold;
        result.configuredMaxDrop  = maxDrop;
        result.changedCategories  = changedCategories;

        if (!absoluteFail && !deltaFail) {
            result.status        = SecurityComparisonResult.Status.Pass;
            result.violationType = SecurityComparisonResult.ViolationType.None;
            result.detailMessage = 'Security score validation passed. Post-deployment score: '
                + post + ' (threshold: ' + threshold + '), delta: ' + delta
                + ' (max drop: ' + maxDrop + ').';
        } else if (absoluteFail && deltaFail) {
            result.status        = SecurityComparisonResult.Status.Fail;
            result.violationType = SecurityComparisonResult.ViolationType.Both;
            result.detailMessage = 'Security score failed both thresholds. Post-deployment score: '
                + post + ' is below absolute threshold ' + threshold
                + '. Score dropped by ' + delta + ' which exceeds max drop of ' + maxDrop + '.';
        } else if (absoluteFail) {
            result.status        = SecurityComparisonResult.Status.Fail;
            result.violationType = SecurityComparisonResult.ViolationType.Absolute;
            result.detailMessage = 'Post-deployment score ' + post
                + ' is below the absolute threshold of ' + threshold + '.';
        } else {
            result.status        = SecurityComparisonResult.Status.Fail;
            result.violationType = SecurityComparisonResult.ViolationType.Delta;
            result.detailMessage = 'Score dropped by ' + delta + ' points which exceeds '
                + 'the maximum allowable drop of ' + maxDrop + '.';
        }

        return result;
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private static List<String> computeChangedCategories(
        SecurityHealthCheckResult preResult,
        SecurityHealthCheckResult postResult
    ) {
        List<String> changed = new List<String>();
        if (preResult.riskCategories == null || postResult.riskCategories == null) {
            return changed;
        }

        // Build a map of post-deployment category scores by name
        Map<String, Integer> postScores = new Map<String, Integer>();
        for (SecurityHealthCheckResult.SecurityRiskCategory cat : postResult.riskCategories) {
            if (cat.categoryName != null) {
                postScores.put(cat.categoryName, cat.score != null ? cat.score : 0);
            }
        }

        // Compare each pre-deployment category against the post-deployment equivalent
        for (SecurityHealthCheckResult.SecurityRiskCategory preCat : preResult.riskCategories) {
            if (preCat.categoryName == null) { continue; }
            Integer preScore = preCat.score != null ? preCat.score : 0;
            if (postScores.containsKey(preCat.categoryName)) {
                Integer postScore = postScores.get(preCat.categoryName);
                if (preScore != postScore) {
                    changed.add(preCat.categoryName);
                }
            } else {
                // Category present in pre but absent in post — consider it changed
                changed.add(preCat.categoryName);
            }
        }

        // Categories present in post but not in pre
        Set<String> preNames = new Set<String>();
        for (SecurityHealthCheckResult.SecurityRiskCategory preCat : preResult.riskCategories) {
            if (preCat.categoryName != null) { preNames.add(preCat.categoryName); }
        }
        for (SecurityHealthCheckResult.SecurityRiskCategory postCat : postResult.riskCategories) {
            if (postCat.categoryName != null && !preNames.contains(postCat.categoryName)) {
                changed.add(postCat.categoryName);
            }
        }

        return changed;
    }

    private static SecurityComparisonResult buildError(Integer preScore, Integer postScore, String message) {
        SecurityComparisonResult result = new SecurityComparisonResult();
        result.status             = SecurityComparisonResult.Status.Error;
        result.violationType      = SecurityComparisonResult.ViolationType.None;
        result.preScore           = preScore;
        result.postScore          = postScore;
        result.scoreDelta         = null;
        result.configuredThreshold = DEFAULT_THRESHOLD;
        result.configuredMaxDrop  = DEFAULT_MAX_DROP;
        result.detailMessage      = message;
        return result;
    }
}
