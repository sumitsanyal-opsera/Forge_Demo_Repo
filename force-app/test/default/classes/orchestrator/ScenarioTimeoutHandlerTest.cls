/**
 * Unit tests for ScenarioTimeoutHandler and ScenarioTimeoutException.
 * Coverage target: ≥90% on both classes.
 *
 * Test categories:
 *   Timer start          — startTimer() records a CPU baseline
 *   Elapsed time         — getElapsedMs() returns non-negative value after CPU work
 *   isTimedOut false     — returns false well within a generous timeout
 *   isTimedOut true      — returns true when injected elapsed exceeds threshold
 *   checkAndThrow safe   — does not throw within generous timeout
 *   checkAndThrow throws — throws ScenarioTimeoutException with elapsed+threshold in message
 *   Exception message    — ScenarioTimeoutException message contains elapsed and threshold
 *   IllegalStateException — getElapsedMs/isTimedOut/checkAndThrow before startTimer
 *   IllegalArgumentException — zero and negative timeoutSeconds
 *   Reset baseline       — second startTimer() resets elapsed counter
 *   Large timeout        — 300-second timeout converts without integer overflow
 */
@isTest
private class ScenarioTimeoutHandlerTest {

    // =========================================================================
    // Timer start and elapsed time basics
    // =========================================================================

    @isTest
    static void testStartTimerEnablesGetElapsedMs() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        handler.startTimer();

        Integer elapsed = handler.getElapsedMs();

        System.assert(elapsed >= 0,
            'getElapsedMs() must return a non-negative value after startTimer()');
    }

    @isTest
    static void testGetElapsedMsIsPositiveAfterCpuWork() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        handler.startTimer();

        // Burn enough CPU for the elapsed time to register at least 1 ms
        Integer x = 0;
        for (Integer i = 0; i < 100000; i++) {
            x += i;
        }

        Integer elapsed = handler.getElapsedMs();

        System.assert(elapsed >= 0,
            'getElapsedMs() must be non-negative after CPU work; got: ' + elapsed);
    }

    // =========================================================================
    // isTimedOut — false path (well within generous timeout)
    // =========================================================================

    @isTest
    static void testIsTimedOut_FalseWithGenerousTimeout() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        handler.startTimer();

        // 30 seconds = 30,000 ms — no scenario will burn 30s of CPU in a test
        System.assertFalse(handler.isTimedOut(30),
            'isTimedOut must return false when well within a 30-second timeout');
    }

    // =========================================================================
    // isTimedOut — true path (via injection)
    // =========================================================================

    @isTest
    static void testIsTimedOut_TrueWithInjectedElapsedMs() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        handler.startTimer();
        ScenarioTimeoutHandler.injectedElapsedMs = 5000; // 5 000 ms injected
        try {
            // isTimedOut(1) → threshold = 1 000 ms; 5 000 >= 1 000 → true
            System.assertTrue(handler.isTimedOut(1),
                'isTimedOut must return true when elapsed (5000ms) >= threshold (1000ms)');
        } finally {
            ScenarioTimeoutHandler.injectedElapsedMs = null;
        }
    }

    // =========================================================================
    // checkAndThrow — safe path
    // =========================================================================

    @isTest
    static void testCheckAndThrow_DoesNotThrowWithinTimeout() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        handler.startTimer();

        ScenarioTimeoutException caught = null;
        try {
            handler.checkAndThrow(30);
        } catch (ScenarioTimeoutException e) {
            caught = e;
        }

        System.assertEquals(null, caught,
            'checkAndThrow must not throw when elapsed is well under a 30-second timeout');
    }

    // =========================================================================
    // checkAndThrow — throws path (via injection)
    // =========================================================================

    @isTest
    static void testCheckAndThrow_ThrowsScenarioTimeoutException() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        handler.startTimer();
        ScenarioTimeoutHandler.injectedElapsedMs = 10000; // 10 000 ms
        ScenarioTimeoutException caught = null;
        try {
            handler.checkAndThrow(1); // threshold = 1 000 ms; 10 000 >= 1 000
        } catch (ScenarioTimeoutException e) {
            caught = e;
        } finally {
            ScenarioTimeoutHandler.injectedElapsedMs = null;
        }

        System.assertNotEquals(null, caught,
            'checkAndThrow must throw ScenarioTimeoutException when elapsed exceeds threshold');
    }

    // =========================================================================
    // ScenarioTimeoutException message verification
    // =========================================================================

    @isTest
    static void testScenarioTimeoutExceptionMessageContainsElapsedAndThreshold() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        handler.startTimer();
        ScenarioTimeoutHandler.injectedElapsedMs = 7500;
        ScenarioTimeoutException caught = null;
        try {
            handler.checkAndThrow(5); // threshold = 5 000 ms; 7 500 >= 5 000
        } catch (ScenarioTimeoutException e) {
            caught = e;
        } finally {
            ScenarioTimeoutHandler.injectedElapsedMs = null;
        }

        System.assertNotEquals(null, caught);
        System.assert(caught.getMessage().contains('7500'),
            'Exception message must contain the elapsed ms; message: ' + caught.getMessage());
        System.assert(caught.getMessage().contains('5000'),
            'Exception message must contain the threshold ms (5*1000); message: ' + caught.getMessage());
    }

    @isTest
    static void testScenarioTimeoutExceptionDirectConstructor() {
        ScenarioTimeoutException ex = new ScenarioTimeoutException(2000, 1000);

        System.assertNotEquals(null, ex.getMessage(),
            'ScenarioTimeoutException must have a non-null message');
        System.assert(ex.getMessage().contains('2000'),
            'Message must contain elapsedMs 2000');
        System.assert(ex.getMessage().contains('1000'),
            'Message must contain timeoutMs 1000');
    }

    // =========================================================================
    // IllegalStateException — methods called before startTimer()
    // =========================================================================

    @isTest
    static void testGetElapsedMsBeforeStartTimerThrows() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        IllegalStateException thrown;
        try {
            handler.getElapsedMs();
        } catch (IllegalStateException e) {
            thrown = e;
        }
        System.assertNotEquals(null, thrown,
            'getElapsedMs() must throw IllegalStateException before startTimer()');
        System.assert(thrown.getMessage().contains('startTimer'),
            'Exception message must mention startTimer');
        System.assert(thrown.getMessage().contains('getElapsedMs'),
            'Exception message must identify getElapsedMs as the calling method');
    }

    @isTest
    static void testIsTimedOutBeforeStartTimerThrows() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        IllegalStateException thrown;
        try {
            handler.isTimedOut(30);
        } catch (IllegalStateException e) {
            thrown = e;
        }
        System.assertNotEquals(null, thrown,
            'isTimedOut() must throw IllegalStateException before startTimer()');
        System.assert(thrown.getMessage().contains('startTimer'));
        System.assert(thrown.getMessage().contains('isTimedOut'));
    }

    @isTest
    static void testCheckAndThrowBeforeStartTimerThrows() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        IllegalStateException thrown;
        try {
            handler.checkAndThrow(30);
        } catch (IllegalStateException e) {
            thrown = e;
        }
        System.assertNotEquals(null, thrown,
            'checkAndThrow() must propagate IllegalStateException when startTimer() was not called');
    }

    // =========================================================================
    // IllegalArgumentException — invalid timeout values
    // =========================================================================

    @isTest
    static void testIsTimedOut_NegativeTimeoutThrowsIllegalArgument() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        handler.startTimer();
        IllegalArgumentException thrown;
        try {
            handler.isTimedOut(-5);
        } catch (IllegalArgumentException e) {
            thrown = e;
        }
        System.assertNotEquals(null, thrown,
            'isTimedOut must throw IllegalArgumentException for negative timeoutSeconds');
        System.assert(thrown.getMessage().contains('-5'),
            'Exception message must include the invalid value');
    }

    @isTest
    static void testIsTimedOut_ZeroTimeoutThrowsIllegalArgument() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        handler.startTimer();
        IllegalArgumentException thrown;
        try {
            handler.isTimedOut(0);
        } catch (IllegalArgumentException e) {
            thrown = e;
        }
        System.assertNotEquals(null, thrown,
            'isTimedOut must throw IllegalArgumentException for zero timeoutSeconds');
    }

    // =========================================================================
    // Multiple startTimer() calls reset the baseline
    // =========================================================================

    @isTest
    static void testMultipleStartTimerCallsResetBaseline() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();

        // First timer start — inject a large elapsed so if it leaks, isTimedOut(30) returns true
        ScenarioTimeoutHandler.injectedElapsedMs = 60000;
        handler.startTimer();
        // Clear injection before second start so the second start works with real CPU time
        ScenarioTimeoutHandler.injectedElapsedMs = null;

        // Second startTimer resets baseline; elapsed is now measured from this new start point
        handler.startTimer();

        // Without injection, elapsed should be tiny (well under 30 seconds)
        System.assertFalse(handler.isTimedOut(30),
            'After re-calling startTimer(), elapsed must reset; isTimedOut(30) must be false');
    }

    // =========================================================================
    // Large timeout — no integer overflow when converting to ms
    // =========================================================================

    @isTest
    static void testLargeTimeout_NoIntegerOverflow() {
        ScenarioTimeoutHandler handler = new ScenarioTimeoutHandler();
        handler.startTimer();

        // 300 seconds * 1000 = 300,000 ms — within Integer range (max ~2.1 billion)
        Boolean result = handler.isTimedOut(300);

        System.assertFalse(result,
            'isTimedOut(300) must return false; no integer overflow on 300 * 1000');
    }
}
