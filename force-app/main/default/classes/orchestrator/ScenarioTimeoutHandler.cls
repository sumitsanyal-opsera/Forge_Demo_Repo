/**
 * Cooperative per-scenario timeout enforcer using Limits.getCpuTime().
 *
 * Usage pattern (called by ScenarioDispatcher around each scenario):
 *   ScenarioTimeoutHandler timer = new ScenarioTimeoutHandler();
 *   timer.startTimer();
 *   // ... inside scenario's long-running operation:
 *   timer.checkAndThrow(context.getGovernorBudget().timeoutSeconds);
 *
 * Design notes:
 *   - Limits.getCpuTime() measures CPU time consumed, not wall-clock time.
 *     DML wait, callout wait, and SOQL execution time are NOT included.
 *   - Timeout enforcement is cooperative — scenarios must call checkAndThrow()
 *     at appropriate checkpoints; the handler cannot forcibly stop a running scenario.
 *   - startTimer() may be called multiple times; each call resets the baseline
 *     to the most recent call (does not accumulate).
 *   - getElapsedMs() and isTimedOut() throw IllegalStateException if called
 *     before startTimer().
 *   - Negative or zero timeoutSeconds throws IllegalArgumentException.
 */
global with sharing class ScenarioTimeoutHandler {

    private Integer startCpuTime;
    private Boolean timerStarted = false;

    @TestVisible
    private static Integer injectedElapsedMs = null;

    // =========================================================================
    // Public API
    // =========================================================================

    global void startTimer() {
        startCpuTime = Limits.getCpuTime();
        timerStarted = true;
    }

    global Integer getElapsedMs() {
        assertTimerStarted('getElapsedMs');
        return injectedElapsedMs != null
            ? injectedElapsedMs
            : (Limits.getCpuTime() - startCpuTime);
    }

    global Boolean isTimedOut(Integer timeoutSeconds) {
        if (timeoutSeconds == null || timeoutSeconds <= 0) {
            throw new IllegalArgumentException(
                'timeoutSeconds must be positive; received: ' + timeoutSeconds);
        }
        assertTimerStarted('isTimedOut');
        return getElapsedMs() >= (timeoutSeconds * 1000);
    }

    global void checkAndThrow(Integer timeoutSeconds) {
        if (isTimedOut(timeoutSeconds)) {
            throw new ScenarioTimeoutException(getElapsedMs(), timeoutSeconds * 1000);
        }
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private void assertTimerStarted(String callerMethod) {
        if (!timerStarted) {
            throw new IllegalStateException(
                'startTimer() must be called before ' + callerMethod + '()');
        }
    }
}
