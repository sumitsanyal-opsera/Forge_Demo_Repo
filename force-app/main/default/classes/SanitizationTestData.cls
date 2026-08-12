/**
 * Reusable PII test fixtures for ErrorSanitizer and related unit tests.
 *
 * Provides static String constants covering each PII pattern type (email,
 * phone, SSN), edge cases (Salesforce record IDs, governor limit messages),
 * mixed-PII strings, a realistic Apex stack trace, and a 10,000-character
 * performance test string. Import in any @isTest class that needs these values.
 */
@isTest
public class SanitizationTestData {

    // -------------------------------------------------------------------------
    // Email fixtures
    // -------------------------------------------------------------------------
    public static final String SIMPLE_EMAIL                = 'user@example.com';
    public static final String SIMPLE_EMAIL_REDACTED       = '[EMAIL_REDACTED]';

    public static final String EMAIL_SUBDOMAIN             = 'user@mail.example.co.uk';
    public static final String EMAIL_SUBDOMAIN_REDACTED    = '[EMAIL_REDACTED]';

    public static final String EMAIL_PLUS_ADDRESSING       = 'user+tag@domain.com';
    public static final String EMAIL_PLUS_ADDRESSING_REDACTED = '[EMAIL_REDACTED]';

    public static final String EMAIL_IN_ERROR_MSG =
        'Validation failed: contact user@example.com to resolve the issue';
    public static final String EMAIL_IN_ERROR_MSG_REDACTED =
        'Validation failed: contact [EMAIL_REDACTED] to resolve the issue';

    public static final String MULTIPLE_EMAILS =
        'Notify admin@example.com and support@company.org about the failure';
    public static final String MULTIPLE_EMAILS_REDACTED =
        'Notify [EMAIL_REDACTED] and [EMAIL_REDACTED] about the failure';

    // -------------------------------------------------------------------------
    // Phone fixtures
    // -------------------------------------------------------------------------
    public static final String PHONE_PARENTHESES           = '(555) 123-4567';
    public static final String PHONE_PARENTHESES_REDACTED  = '[PHONE_REDACTED]';

    public static final String PHONE_DASHES                = '555-123-4567';
    public static final String PHONE_DASHES_REDACTED       = '[PHONE_REDACTED]';

    public static final String PHONE_DOTS                  = '555.123.4567';
    public static final String PHONE_DOTS_REDACTED         = '[PHONE_REDACTED]';

    public static final String PHONE_COUNTRY_CODE          = '+15551234567';
    public static final String PHONE_COUNTRY_CODE_REDACTED = '[PHONE_REDACTED]';

    public static final String PHONE_IN_VALIDATION_MSG =
        'Invalid phone number provided: 555-867-5309 is not in the approved list';
    public static final String PHONE_IN_VALIDATION_MSG_REDACTED =
        'Invalid phone number provided: [PHONE_REDACTED] is not in the approved list';

    // -------------------------------------------------------------------------
    // SSN fixtures
    // -------------------------------------------------------------------------
    public static final String SSN_DASHED                  = '123-45-6789';
    public static final String SSN_DASHED_REDACTED         = '[SSN_REDACTED]';

    public static final String SSN_CONTINUOUS              = '123456789';
    public static final String SSN_CONTINUOUS_REDACTED     = '[SSN_REDACTED]';

    public static final String SSN_IN_ERROR_MSG =
        'Account record contains SSN 987-65-4321 which failed verification';
    public static final String SSN_IN_ERROR_MSG_REDACTED =
        'Account record contains SSN [SSN_REDACTED] which failed verification';

    // -------------------------------------------------------------------------
    // Mixed PII — all three patterns in one string
    // -------------------------------------------------------------------------
    public static final String MIXED_PII_STRING =
        'Contact: user@example.com | Phone: 555-123-4567 | SSN: 123-45-6789';
    public static final String MIXED_PII_STRING_REDACTED =
        'Contact: [EMAIL_REDACTED] | Phone: [PHONE_REDACTED] | SSN: [SSN_REDACTED]';

    // -------------------------------------------------------------------------
    // False-positive prevention fixtures (should NOT be masked)
    // -------------------------------------------------------------------------

    // 18-character Salesforce record ID — alphanumeric, no 9-digit pure sequence
    public static final String SALESFORCE_RECORD_ID_STRING =
        'Updated record: 001xx000003DGbYAAW in the system';

    // Governor limit error — digits separated by text, not phone pattern
    public static final String GOVERNOR_LIMIT_ERROR =
        'Too many SOQL queries: 101 of 100 allowed';

    // Plain text with no PII
    public static final String NO_PII_STRING =
        'Smoke test scenario AccountCrudScenario completed in 247ms with status Passed';

    // -------------------------------------------------------------------------
    // Apex stack trace — class/method names must be preserved after sanitization
    // -------------------------------------------------------------------------
    public static final String APEX_STACK_TRACE_WITH_PII =
        'Class.AccountCrudScenario.execute: line 42, column 1\n' +
        'Error: Validation failed for email address test@example.com\n' +
        'Class.SmokeTestOrchestrator.runScenario: line 88, column 1\n' +
        'Class.SmokeTestOrchestratorQueueable.execute: line 18, column 1';

    public static final String APEX_STACK_TRACE_REDACTED =
        'Class.AccountCrudScenario.execute: line 42, column 1\n' +
        'Error: Validation failed for email address [EMAIL_REDACTED]\n' +
        'Class.SmokeTestOrchestrator.runScenario: line 88, column 1\n' +
        'Class.SmokeTestOrchestratorQueueable.execute: line 18, column 1';

    // -------------------------------------------------------------------------
    // Performance fixture — 10,000-character string with no PII
    // -------------------------------------------------------------------------
    public static final String LONG_STRING_10K;

    static {
        // Build a realistic 10K diagnostic string with class references and counts
        // but no PII, to test that the sanitizer can process it within 50ms CPU.
        String chunk = 'SmokeTestOrchestrator executed scenario AccountCrudScenario ' +
                       'status=Passed cpuMs=123 soqlCount=5 dmlCount=2 result=OK ';
        String built = '';
        Integer target = 10000;
        while (built.length() < target) {
            built += chunk;
        }
        LONG_STRING_10K = built.left(target);
    }
}
