/**
 * Typed result returned by SecurityScoreComparator.compare().
 *
 * Status values:
 *   Pass  — both absolute and delta thresholds satisfied
 *   Fail  — one or both thresholds violated (see violationType for details)
 *   Error — one or both inputs were null or had ERROR/SKIPPED status
 *
 * ViolationType values:
 *   None     — no threshold violated (status = Pass)
 *   Absolute — post-deployment score below configuredThreshold
 *   Delta    — score drop exceeds configuredMaxDrop
 *   Both     — both thresholds violated simultaneously
 */
public class SecurityComparisonResult {

    public enum Status        { Pass, Fail, Error }
    public enum ViolationType { None, Absolute, Delta, Both }

    public Status        status;
    public ViolationType violationType;
    public Integer       preScore;
    public Integer       postScore;
    public Integer       scoreDelta;
    public Integer       configuredThreshold;
    public Integer       configuredMaxDrop;
    public List<String>  changedCategories;
    public String        detailMessage;

    public SecurityComparisonResult() {
        this.changedCategories = new List<String>();
    }
}
