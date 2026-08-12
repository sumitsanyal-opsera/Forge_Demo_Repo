/**
 * Security-critical validator for custom SOQL queries stored in SmokeTestChecklist__mdt.
 *
 * Implements defense-in-depth (OWASP A05) with five independent validation layers:
 *   1. Syntax — Database.getQueryLocator() try-catch
 *   2. DML keyword scan — regex for INSERT/UPDATE/DELETE/UPSERT/MERGE/UNDELETE
 *   3. Restricted object allow-list — rejects sensitive schema objects
 *   4. LIMIT clause — required; must not exceed 10,000 rows
 *   5. Binding variable detection — rejects colon-prefixed variables
 *
 * All failures are collected and returned together (not just the first one found).
 */
public with sharing class ChecklistQueryValidator {

    private static final Integer MAX_LIMIT = 10000;

    private static final Set<String> DML_KEYWORDS = new Set<String>{
        'INSERT', 'UPDATE', 'DELETE', 'UPSERT', 'MERGE', 'UNDELETE'
    };

    // Objects that expose security-sensitive data; queries against these are rejected.
    private static final Set<String> RESTRICTED_OBJECTS = new Set<String>{
        'OAUTHTOKEN', 'LOGINHISTORY', 'AUTHSESSION', 'SETUPAUDITTRAIL',
        'USERLOGIN', 'SITEHISTORY', 'USERAUTHCREDENTIAL'
    };

    /**
     * Validates soqlQuery and returns a ValidationResult with all failures listed.
     * Never throws — exceptions from Database.getQueryLocator() are caught and
     * included in errorMessages.
     */
    public static ValidationResult validate(String soqlQuery) {
        List<String> errors = new List<String>();

        if (String.isBlank(soqlQuery)) {
            errors.add('Query is null or empty');
            return new ValidationResult(false, errors);
        }

        // 1. Syntax check — getQueryLocator validates SOQL without executing
        try {
            Database.getQueryLocator(soqlQuery);
        } catch (Exception e) {
            errors.add('Invalid SOQL syntax: ' + e.getMessage());
        }

        // 2. DML keyword check (case-insensitive, word-boundary anchored)
        String upper = soqlQuery.toUpperCase();
        for (String kw : DML_KEYWORDS) {
            Matcher m = Pattern.compile('\\b' + kw + '\\b').matcher(upper);
            if (m.find()) {
                errors.add('Query contains prohibited DML keyword: ' + kw);
            }
        }

        // 3. Restricted object check — extract FROM clause object name
        Matcher fromMatcher = Pattern.compile('(?i)\\bFROM\\s+(\\w+)').matcher(soqlQuery);
        if (fromMatcher.find()) {
            String objectName = fromMatcher.group(1).toUpperCase();
            if (RESTRICTED_OBJECTS.contains(objectName)) {
                errors.add('Query references restricted object: ' + fromMatcher.group(1));
            }
        }

        // 4. LIMIT clause — must be present and must not exceed MAX_LIMIT
        Matcher limitMatcher = Pattern.compile('(?i)\\bLIMIT\\s+(\\d+)').matcher(soqlQuery);
        if (!limitMatcher.find()) {
            errors.add('Query must include a LIMIT clause to prevent governor limit violations');
        } else {
            Integer limitVal = Integer.valueOf(limitMatcher.group(1));
            if (limitVal > MAX_LIMIT) {
                errors.add('Query LIMIT ' + limitVal + ' exceeds maximum allowed value of ' + MAX_LIMIT);
            }
        }

        // 5. Binding variable check — colon-prefixed tokens are unsafe in dynamic SOQL
        if (Pattern.compile(':\\w+').matcher(soqlQuery).find()) {
            errors.add('Query must not contain dynamic binding variables (colon-prefixed values like :varName)');
        }

        return new ValidationResult(errors.isEmpty(), errors);
    }
}
