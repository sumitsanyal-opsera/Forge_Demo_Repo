/**
 * Unit tests for ErrorSanitizer — PII masking utility.
 *
 * 20 test methods organised by category:
 *   Edge cases      (3)  — null, empty, no-match
 *   Email detection (5)  — standard, subdomain, plus-addressing, embedded, multiple
 *   Phone detection (5)  — parentheses, dashes, dots, country code, embedded
 *   SSN detection   (3)  — dashed, continuous, embedded
 *   Mixed patterns  (1)  — all three in one string
 *   False positives (2)  — Salesforce record ID, governor limit number
 *   Stack trace     (1)  — class/method names preserved
 *   Performance     (1)  — 10 K string under 50 ms CPU
 */
@isTest
private class ErrorSanitizerTest {

    // =========================================================================
    // Edge cases
    // =========================================================================

    @isTest
    static void testSanitize_nullInputReturnsNull() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(null);
        Test.stopTest();

        System.assertEquals(null, result, 'null input should return null');
    }

    @isTest
    static void testSanitize_emptyInputReturnsEmpty() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize('');
        Test.stopTest();

        System.assertEquals('', result, 'empty input should return empty string');
    }

    @isTest
    static void testSanitize_noPiiUnchanged() {
        String input = SanitizationTestData.NO_PII_STRING;
        Test.startTest();
        String result = ErrorSanitizer.sanitize(input);
        Test.stopTest();

        System.assertEquals(input, result, 'string with no PII should be returned unchanged');
    }

    // =========================================================================
    // Email detection (5 tests)
    // =========================================================================

    @isTest
    static void testEmail_standardFormat() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.SIMPLE_EMAIL);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.SIMPLE_EMAIL_REDACTED, result,
            'standard email address should be replaced with [EMAIL_REDACTED]');
    }

    @isTest
    static void testEmail_withSubdomain() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.EMAIL_SUBDOMAIN);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.EMAIL_SUBDOMAIN_REDACTED, result,
            'email with subdomain should be replaced with [EMAIL_REDACTED]');
    }

    @isTest
    static void testEmail_plusAddressing() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.EMAIL_PLUS_ADDRESSING);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.EMAIL_PLUS_ADDRESSING_REDACTED, result,
            'plus-addressed email (user+tag@domain.com) should be replaced');
    }

    @isTest
    static void testEmail_embeddedInErrorMessage() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.EMAIL_IN_ERROR_MSG);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.EMAIL_IN_ERROR_MSG_REDACTED, result,
            'email embedded in an error message should be replaced while surrounding text is preserved');
        System.assert(result.contains('Validation failed:'),
            'error message context before email should be preserved');
        System.assert(result.contains('to resolve the issue'),
            'error message context after email should be preserved');
    }

    @isTest
    static void testEmail_multipleOccurrencesAllReplaced() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.MULTIPLE_EMAILS);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.MULTIPLE_EMAILS_REDACTED, result,
            'all email occurrences in a string should be replaced, not just the first');
        System.assertEquals(
            2, result.countMatches('[EMAIL_REDACTED]'),
            'two emails in input should produce two [EMAIL_REDACTED] tokens');
    }

    // =========================================================================
    // Phone detection (5 tests)
    // =========================================================================

    @isTest
    static void testPhone_parenthesesFormat() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.PHONE_PARENTHESES);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.PHONE_PARENTHESES_REDACTED, result,
            '(XXX) XXX-XXXX format phone should be replaced with [PHONE_REDACTED]');
    }

    @isTest
    static void testPhone_dashesFormat() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.PHONE_DASHES);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.PHONE_DASHES_REDACTED, result,
            'XXX-XXX-XXXX format phone should be replaced with [PHONE_REDACTED]');
    }

    @isTest
    static void testPhone_dotsFormat() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.PHONE_DOTS);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.PHONE_DOTS_REDACTED, result,
            'XXX.XXX.XXXX format phone should be replaced with [PHONE_REDACTED]');
    }

    @isTest
    static void testPhone_countryCodeNoSeparators() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.PHONE_COUNTRY_CODE);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.PHONE_COUNTRY_CODE_REDACTED, result,
            '+1XXXXXXXXXX country code format should be replaced with [PHONE_REDACTED]');
    }

    @isTest
    static void testPhone_embeddedInValidationMessage() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.PHONE_IN_VALIDATION_MSG);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.PHONE_IN_VALIDATION_MSG_REDACTED, result,
            'phone number embedded in a validation rule message should be replaced');
        System.assert(result.contains('Invalid phone number provided:'),
            'message context before phone should be preserved');
    }

    // =========================================================================
    // SSN detection (3 tests)
    // =========================================================================

    @isTest
    static void testSSN_dashedFormat() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.SSN_DASHED);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.SSN_DASHED_REDACTED, result,
            'XXX-XX-XXXX dashed SSN format should be replaced with [SSN_REDACTED]');
    }

    @isTest
    static void testSSN_continuousDigits() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.SSN_CONTINUOUS);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.SSN_CONTINUOUS_REDACTED, result,
            '9 consecutive digits (XXXXXXXXX) should be replaced with [SSN_REDACTED]');
    }

    @isTest
    static void testSSN_embeddedInErrorMessage() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.SSN_IN_ERROR_MSG);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.SSN_IN_ERROR_MSG_REDACTED, result,
            'SSN embedded in an error message should be replaced');
        System.assert(result.contains('Account record contains SSN'),
            'message context before SSN should be preserved');
    }

    // =========================================================================
    // Mixed patterns (1 test)
    // =========================================================================

    @isTest
    static void testMixed_allThreePatternsInOneString() {
        Test.startTest();
        String result = ErrorSanitizer.sanitize(SanitizationTestData.MIXED_PII_STRING);
        Test.stopTest();

        System.assertEquals(SanitizationTestData.MIXED_PII_STRING_REDACTED, result,
            'email, phone, and SSN in a single string should all be replaced');
        System.assert(result.contains('[EMAIL_REDACTED]'),  'email should be replaced');
        System.assert(result.contains('[PHONE_REDACTED]'),  'phone should be replaced');
        System.assert(result.contains('[SSN_REDACTED]'),    'SSN should be replaced');
        System.assert(!result.contains('@'),
            'no raw @ characters should remain after sanitization');
    }

    // =========================================================================
    // False-positive prevention (2 tests)
    // =========================================================================

    @isTest
    static void testFalsePositive_salesforceRecordIdNotMasked() {
        String input = SanitizationTestData.SALESFORCE_RECORD_ID_STRING;
        Test.startTest();
        String result = ErrorSanitizer.sanitize(input);
        Test.stopTest();

        System.assertEquals(input, result,
            'Salesforce 18-character record ID should not be falsely masked as an SSN or phone number');
        System.assert(result.contains('001xx000003DGbYAAW'),
            'record ID must survive sanitization intact');
    }

    @isTest
    static void testFalsePositive_governorLimitNumberNotMasked() {
        String input = SanitizationTestData.GOVERNOR_LIMIT_ERROR;
        Test.startTest();
        String result = ErrorSanitizer.sanitize(input);
        Test.stopTest();

        System.assertEquals(input, result,
            'governor limit error message ("101 of 100") should not be falsely masked as a phone number');
        System.assert(result.contains('101 of 100'),
            'limit counts must survive sanitization intact');
    }

    // =========================================================================
    // Stack trace preservation (1 test)
    // =========================================================================

    @isTest
    static void testSanitizeStackTrace_preservesClassNamesAndLineNumbers() {
        Test.startTest();
        String result = ErrorSanitizer.sanitizeStackTrace(
            SanitizationTestData.APEX_STACK_TRACE_WITH_PII
        );
        Test.stopTest();

        System.assertEquals(SanitizationTestData.APEX_STACK_TRACE_REDACTED, result,
            'PII in stack trace message lines should be replaced');
        System.assert(result.contains('Class.AccountCrudScenario.execute: line 42, column 1'),
            'Apex class name and line number on first stack frame must be preserved');
        System.assert(result.contains('Class.SmokeTestOrchestrator.runScenario: line 88, column 1'),
            'Apex class name and line number on third stack frame must be preserved');
        System.assert(result.contains('Class.SmokeTestOrchestratorQueueable.execute: line 18, column 1'),
            'Apex class name and line number on fourth stack frame must be preserved');
        System.assert(result.contains('[EMAIL_REDACTED]'),
            'email address in the error line should be replaced');
        System.assert(!result.contains('test@example.com'),
            'raw email address must not appear in sanitized trace');
    }

    // =========================================================================
    // Additional edge cases
    // =========================================================================

    @isTest
    static void testSanitizeStackTrace_nullInput() {
        Test.startTest();
        String result = ErrorSanitizer.sanitizeStackTrace(null);
        Test.stopTest();

        System.assertEquals(null, result, 'sanitizeStackTrace(null) should return null');
    }

    @isTest
    static void testSanitizeStackTrace_emptyInput() {
        Test.startTest();
        String result = ErrorSanitizer.sanitizeStackTrace('');
        Test.stopTest();

        System.assertEquals('', result, 'sanitizeStackTrace(\'\') should return empty string');
    }

    // =========================================================================
    // Performance test (1 test)
    // =========================================================================

    @isTest
    static void testPerformance_10kStringUnder50msCpu() {
        String longString = SanitizationTestData.LONG_STRING_10K;
        System.assertEquals(10000, longString.length(), 'test fixture must be exactly 10000 chars');

        Test.startTest();
        Integer cpuBefore = Limits.getCpuTime();
        String result     = ErrorSanitizer.sanitize(longString);
        Integer cpuAfter  = Limits.getCpuTime();
        Test.stopTest();

        Integer elapsed = cpuAfter - cpuBefore;
        System.assert(
            elapsed < 50,
            'sanitizing a 10,000-character string must complete in under 50ms CPU time. Actual: ' + elapsed + 'ms'
        );
        System.assert(result != null,
            'performance test must return a non-null result');
        System.assertEquals(10000, result.length(),
            'sanitizing a string with no PII should return a string of the same length');
    }
}
