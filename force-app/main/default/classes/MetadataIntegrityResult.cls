/**
 * Aggregate result returned by MetadataIntegrityService.verify().
 *
 * totalComponents counts only real manifest components (not service messages
 * such as empty-manifest warnings or parse errors). passedCount, failedCount,
 * and warningCount include all results so the caller can detect service-level
 * issues even when totalComponents is zero.
 */
public class MetadataIntegrityResult {

    public Integer totalComponents   { get; private set; }
    public Integer passedCount       { get; private set; }
    public Integer failedCount       { get; private set; }
    public Integer warningCount      { get; private set; }
    public List<MetadataCheckResult> checkResults { get; private set; }
    public DateTime executionTimestamp { get; private set; }

    public MetadataIntegrityResult() {
        this.totalComponents    = 0;
        this.passedCount        = 0;
        this.failedCount        = 0;
        this.warningCount       = 0;
        this.checkResults       = new List<MetadataCheckResult>();
        this.executionTimestamp = Datetime.now();
    }

    /**
     * Adds a result for a real manifest component.
     * Increments totalComponents and the appropriate status counter.
     */
    public void addComponentResult(MetadataCheckResult result) {
        totalComponents++;
        tally(result);
        checkResults.add(result);
    }

    /**
     * Adds a service-level message (e.g., empty manifest warning, parse error).
     * Does NOT increment totalComponents but does tally the status counter.
     */
    public void addServiceMessage(MetadataCheckResult result) {
        tally(result);
        checkResults.add(result);
    }

    private void tally(MetadataCheckResult result) {
        if (result.status == MetadataCheckResult.Status.PASS)         { passedCount++;  }
        else if (result.status == MetadataCheckResult.Status.FAIL)    { failedCount++;  }
        else if (result.status == MetadataCheckResult.Status.WARNING) { warningCount++; }
    }
}
