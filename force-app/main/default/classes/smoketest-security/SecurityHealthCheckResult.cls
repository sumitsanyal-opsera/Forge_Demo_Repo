/**
 * Strongly-typed wrapper for a Tooling API SecurityHealthCheck query result.
 *
 * Constructed via the static factory methods (success(), error(), skipped()) —
 * the public constructor is also available for direct field assignment by the parser.
 *
 * ThresholdStatus values:
 *   PASS    — score retrieved; org is above threshold
 *   FAIL    — score retrieved; org is below threshold
 *   ERROR   — HTTP or parse failure; overallScore is -1
 *   SKIPPED — pre-flight check blocked the callout (e.g. API budget exhausted)
 */
public class SecurityHealthCheckResult {

    public enum ThresholdStatus { PASS, FAIL, ERROR, SKIPPED }

    // =========================================================================
    // Inner class: SecuritySetting
    // =========================================================================

    public class SecuritySetting {
        public String settingName;
        public String value;
        public String recommendation;

        public SecuritySetting(String settingName, String value, String recommendation) {
            this.settingName    = settingName;
            this.value          = value;
            this.recommendation = recommendation;
        }

        public SecuritySetting() {}
    }

    // =========================================================================
    // Inner class: SecurityRiskCategory
    // =========================================================================

    public class SecurityRiskCategory {
        public String              categoryName;
        public Integer             score;
        public List<SecuritySetting> settings;

        public SecurityRiskCategory(String categoryName, Integer score, List<SecuritySetting> settings) {
            this.categoryName = categoryName;
            this.score        = score;
            this.settings     = settings != null ? settings : new List<SecuritySetting>();
        }

        public SecurityRiskCategory() {
            this.settings = new List<SecuritySetting>();
        }
    }

    // =========================================================================
    // Result fields
    // =========================================================================

    public Integer                    overallScore;
    public List<SecurityRiskCategory> riskCategories;
    public List<String>               remediationLinks;
    public Datetime                   capturedAt;
    public ThresholdStatus            thresholdStatus;
    public String                     diagnosticMessage;

    public SecurityHealthCheckResult() {
        this.riskCategories  = new List<SecurityRiskCategory>();
        this.remediationLinks = new List<String>();
        this.capturedAt      = Datetime.now();
    }

    // =========================================================================
    // Static factory methods
    // =========================================================================

    public static SecurityHealthCheckResult error(String diagnosticMessage) {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore      = -1;
        r.thresholdStatus   = ThresholdStatus.ERROR;
        r.diagnosticMessage = diagnosticMessage;
        return r;
    }

    public static SecurityHealthCheckResult skipped(String diagnosticMessage) {
        SecurityHealthCheckResult r = new SecurityHealthCheckResult();
        r.overallScore      = -1;
        r.thresholdStatus   = ThresholdStatus.SKIPPED;
        r.diagnosticMessage = diagnosticMessage;
        return r;
    }
}
