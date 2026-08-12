global with sharing class ScenarioResult {

    global final Boolean passed;
    global final String  errorType;
    // errorDetail must be sanitized by the caller — no raw stack traces or PII (see ErrorSanitizer)
    global final String  errorDetail;
    global final Long    durationMs;
    global final String  scenarioName;

    private ScenarioResult(
        Boolean passed,
        String  scenarioName,
        Long    durationMs,
        String  errorType,
        String  errorDetail
    ) {
        this.passed       = passed;
        this.scenarioName = scenarioName;
        this.durationMs   = durationMs;
        this.errorType    = errorType;
        this.errorDetail  = errorDetail;
    }

    global static ScenarioResult success(String scenarioName, Long durationMs) {
        return new ScenarioResult(true, scenarioName, durationMs, null, null);
    }

    global static ScenarioResult failure(
        String scenarioName,
        Long   durationMs,
        String errorType,
        String errorDetail
    ) {
        return new ScenarioResult(false, scenarioName, durationMs, errorType, errorDetail);
    }
}
