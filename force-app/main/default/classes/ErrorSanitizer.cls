/**
 * Stateless PII-masking utility for error messages and stack traces.
 *
 * Replaces detected PII patterns (email, US phone, SSN) with clearly labelled
 * redaction placeholders before any persistence to SmokeTestResult__c or
 * transmission via API responses and alert notifications. Mandated by the
 * GDPR/CCPA policy and OWASP A10 (sensitive data exposure prevention).
 *
 * Usage:
 *   String safe = ErrorSanitizer.sanitize(rawErrorMessage);
 *   String safeTrace = ErrorSanitizer.sanitizeStackTrace(apexStackTrace);
 *
 * The PatternReplacement inner class allows future patterns (credit card, IP
 * address) to be added to PATTERNS without touching the sanitize loop.
 */
public with sharing class ErrorSanitizer {

    // CPU budget guard: return partially-sanitized output if any single call
    // exceeds this many milliseconds of CPU time to protect governor limits.
    @TestVisible
    private static final Integer CPU_BUDGET_MS = 50;

    // -------------------------------------------------------------------------
    // Compiled regex patterns — instantiated once per class-load, not per call.
    // -------------------------------------------------------------------------

    // Email: simplified RFC 5322 local-part@domain.TLD
    // Handles plus-addressing (user+tag@domain.com), dots and underscores in
    // local part, and multi-level domains (user@sub.domain.co.uk).
    // Does NOT match bare hostnames with no TLD (reduces false positives).
    private static final Pattern EMAIL_PATTERN = Pattern.compile(
        '[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}'
    );

    // US Phone: requires at least one separator between digit groups so that
    // governor-limit integers ("101 of 100") and short numeric sequences are
    // not falsely matched.
    // Matches: (XXX) XXX-XXXX | XXX-XXX-XXXX | XXX.XXX.XXXX | XXX XXX XXXX
    //          +1(XXX) XXX-XXXX | +1 XXX-XXX-XXXX | +1XXXXXXXXXX
    private static final Pattern PHONE_PATTERN = Pattern.compile(
        '(?:\\+1)?\\([0-9]{3}\\)[\\s.\\-]?[0-9]{3}[\\s.\\-][0-9]{4}' +
        '|(?:\\+1[\\s.\\-]?)?[0-9]{3}[\\s.\\-][0-9]{3}[\\s.\\-][0-9]{4}' +
        '|\\+1[0-9]{10}'
    );

    // SSN: XXX-XX-XXXX (dashed) or exactly 9 consecutive digits.
    // Word boundaries (\b) prevent matching within longer alphanumeric strings
    // such as Salesforce 18-character record IDs or timestamps.
    private static final Pattern SSN_PATTERN = Pattern.compile(
        '\\b[0-9]{3}-[0-9]{2}-[0-9]{4}\\b' +
        '|\\b[0-9]{9}\\b'
    );

    private static final String EMAIL_REPLACEMENT = '[EMAIL_REDACTED]';
    private static final String PHONE_REPLACEMENT = '[PHONE_REDACTED]';
    private static final String SSN_REPLACEMENT   = '[SSN_REDACTED]';
    private static final String TIMEOUT_MARKER    = '[SANITIZATION_TIMEOUT]';

    // -------------------------------------------------------------------------
    // PatternReplacement — extensibility hook for future PII pattern additions.
    // -------------------------------------------------------------------------
    @TestVisible
    private class PatternReplacement {
        Pattern pat;
        String  replacement;
        String  name;

        PatternReplacement(Pattern p, String r, String n) {
            pat         = p;
            replacement = r;
            name        = n;
        }
    }

    // Replacement order: SSN first (most specific 9-digit sequence), then email
    // (@ character makes it unambiguous), then phone (broadest match).
    // Ordering prevents partial matches from corrupting subsequent patterns.
    private static final List<PatternReplacement> PATTERNS = new List<PatternReplacement>{
        new PatternReplacement(SSN_PATTERN,   SSN_REPLACEMENT,   'SSN'),
        new PatternReplacement(EMAIL_PATTERN, EMAIL_REPLACEMENT, 'EMAIL'),
        new PatternReplacement(PHONE_PATTERN, PHONE_REPLACEMENT, 'PHONE')
    };

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Replaces all detected PII patterns in {@code input} with redaction placeholders.
     *
     * Returns null if input is null; empty string if input is empty.
     * If processing exceeds CPU_BUDGET_MS, returns the partially-sanitized
     * string with '[SANITIZATION_TIMEOUT]' appended rather than blocking
     * the calling transaction.
     */
    public static String sanitize(String input) {
        if (input == null)       { return null; }
        if (input.length() == 0) { return '';   }

        Integer cpuStart = Limits.getCpuTime();
        String  result   = input;

        for (PatternReplacement pr : PATTERNS) {
            if ((Limits.getCpuTime() - cpuStart) >= CPU_BUDGET_MS) {
                return result + TIMEOUT_MARKER;
            }
            Matcher m = pr.pat.matcher(result);
            result = m.replaceAll(pr.replacement);
        }

        return result;
    }

    /**
     * Splits an Apex stack trace on newlines, sanitizes each line individually,
     * then rejoins — preserving class names, line numbers, and method signatures
     * while masking any PII in the error message portions.
     */
    public static String sanitizeStackTrace(String stackTrace) {
        if (stackTrace == null)       { return null; }
        if (stackTrace.length() == 0) { return '';   }

        List<String> lines     = stackTrace.split('\n');
        List<String> sanitized = new List<String>();
        for (String line : lines) {
            sanitized.add(sanitize(line));
        }
        return String.join(sanitized, '\n');
    }
}
