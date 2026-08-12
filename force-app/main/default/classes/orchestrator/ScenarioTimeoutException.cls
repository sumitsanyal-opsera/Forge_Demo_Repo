global with sharing class ScenarioTimeoutException extends Exception {

    global ScenarioTimeoutException(Integer elapsedMs, Integer timeoutMs) {
        this.setMessage(
            'Scenario timed out: elapsed CPU time ' + elapsedMs
            + 'ms exceeded threshold ' + timeoutMs + 'ms');
    }
}
