@isTest
private class ChecklistQueryValidatorTest {

    // -------------------------------------------------------------------------
    // Null / empty input
    // -------------------------------------------------------------------------

    @isTest
    static void validate_nullInput_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate(null);
        System.assertEquals(false, result.isValid, 'Null query should be invalid');
        System.assertEquals(1, result.errorMessages.size(),
            'Should have exactly one error for null input');
        System.assert(result.errorMessages[0].contains('null or empty'),
            'Error should describe null/empty condition: ' + result.errorMessages[0]);
    }

    @isTest
    static void validate_emptyString_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate('');
        System.assertEquals(false, result.isValid, 'Empty query should be invalid');
        System.assert(!result.errorMessages.isEmpty(), 'Should have at least one error');
    }

    @isTest
    static void validate_blankWhitespace_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate('   ');
        System.assertEquals(false, result.isValid, 'Whitespace-only query should be invalid');
    }

    // -------------------------------------------------------------------------
    // Valid query
    // -------------------------------------------------------------------------

    @isTest
    static void validate_validSelectQuery_returnsValid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'SELECT Id FROM User LIMIT 1'
        );
        System.assertEquals(true, result.isValid,
            'Valid SELECT query should pass all checks. Errors: ' +
            String.join(result.errorMessages, ', '));
        System.assertEquals(0, result.errorMessages.size(),
            'Should have no error messages for a valid query');
    }

    @isTest
    static void validate_validQueryWithWhereAndLimit_returnsValid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'SELECT Id, Name FROM Account WHERE IsDeleted = false LIMIT 100'
        );
        System.assertEquals(true, result.isValid,
            'Valid query with WHERE and LIMIT should pass. Errors: ' +
            String.join(result.errorMessages, ', '));
    }

    // -------------------------------------------------------------------------
    // Syntax check
    // -------------------------------------------------------------------------

    @isTest
    static void validate_invalidSyntax_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'SELECT BadFieldXYZ_NONEXISTENT FROM Account LIMIT 1'
        );
        System.assertEquals(false, result.isValid,
            'Query with invalid field name should fail syntax check');
        Boolean hasSyntaxError = false;
        for (String err : result.errorMessages) {
            if (err.containsIgnoreCase('syntax') || err.containsIgnoreCase('Invalid')) {
                hasSyntaxError = true;
                break;
            }
        }
        System.assert(hasSyntaxError,
            'Should include a syntax error message. Errors: ' +
            String.join(result.errorMessages, ', '));
    }

    // -------------------------------------------------------------------------
    // DML keyword check
    // -------------------------------------------------------------------------

    @isTest
    static void validate_insertKeyword_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'INSERT INTO Account (Name) VALUES (\'Test\') LIMIT 1'
        );
        System.assertEquals(false, result.isValid, 'INSERT keyword should be rejected');
        Boolean hasDmlError = false;
        for (String err : result.errorMessages) {
            if (err.containsIgnoreCase('DML') || err.containsIgnoreCase('INSERT')) {
                hasDmlError = true;
                break;
            }
        }
        System.assert(hasDmlError,
            'Should include a DML keyword error. Errors: ' +
            String.join(result.errorMessages, ', '));
    }

    @isTest
    static void validate_deleteKeyword_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'DELETE FROM Account WHERE Id = \'001xx\' LIMIT 1'
        );
        System.assertEquals(false, result.isValid, 'DELETE keyword should be rejected');
    }

    @isTest
    static void validate_updateKeyword_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'UPDATE Account SET Name = \'Test\' LIMIT 1'
        );
        System.assertEquals(false, result.isValid, 'UPDATE keyword should be rejected');
    }

    @isTest
    static void validate_upsertKeyword_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'UPSERT Account LIMIT 1'
        );
        System.assertEquals(false, result.isValid, 'UPSERT keyword should be rejected');
    }

    // -------------------------------------------------------------------------
    // Restricted object check
    // -------------------------------------------------------------------------

    @isTest
    static void validate_restrictedObjectOAuthToken_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'SELECT Id FROM OAuthToken LIMIT 1'
        );
        System.assertEquals(false, result.isValid,
            'Query against OAuthToken should be rejected');
        Boolean hasObjectError = false;
        for (String err : result.errorMessages) {
            if (err.containsIgnoreCase('restricted') || err.containsIgnoreCase('OAuthToken')) {
                hasObjectError = true;
                break;
            }
        }
        System.assert(hasObjectError,
            'Should report restricted object error. Errors: ' +
            String.join(result.errorMessages, ', '));
    }

    @isTest
    static void validate_restrictedObjectSetupAuditTrail_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'SELECT Id FROM SetupAuditTrail LIMIT 1'
        );
        System.assertEquals(false, result.isValid,
            'Query against SetupAuditTrail should be rejected');
    }

    // -------------------------------------------------------------------------
    // LIMIT clause check
    // -------------------------------------------------------------------------

    @isTest
    static void validate_noLimitClause_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'SELECT Id FROM User'
        );
        System.assertEquals(false, result.isValid,
            'Query without LIMIT clause should be rejected');
        Boolean hasLimitError = false;
        for (String err : result.errorMessages) {
            if (err.containsIgnoreCase('LIMIT')) {
                hasLimitError = true;
                break;
            }
        }
        System.assert(hasLimitError,
            'Should report missing LIMIT error. Errors: ' +
            String.join(result.errorMessages, ', '));
    }

    @isTest
    static void validate_limitExceedsMaximum_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'SELECT Id FROM Account LIMIT 10001'
        );
        System.assertEquals(false, result.isValid,
            'Query with LIMIT > 10000 should be rejected');
        Boolean hasLimitError = false;
        for (String err : result.errorMessages) {
            if (err.containsIgnoreCase('LIMIT') || err.containsIgnoreCase('10000')) {
                hasLimitError = true;
                break;
            }
        }
        System.assert(hasLimitError,
            'Should report LIMIT exceeded error. Errors: ' +
            String.join(result.errorMessages, ', '));
    }

    @isTest
    static void validate_limitAtMaximum_returnsValid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'SELECT Id FROM Account LIMIT 10000'
        );
        System.assertEquals(true, result.isValid,
            'Query with LIMIT = 10000 should be valid. Errors: ' +
            String.join(result.errorMessages, ', '));
    }

    // -------------------------------------------------------------------------
    // Binding variable check
    // -------------------------------------------------------------------------

    @isTest
    static void validate_bindingVariable_returnsInvalid() {
        ValidationResult result = ChecklistQueryValidator.validate(
            'SELECT Id FROM User WHERE Id = :userId LIMIT 1'
        );
        System.assertEquals(false, result.isValid,
            'Query with binding variable should be rejected');
        Boolean hasBindingError = false;
        for (String err : result.errorMessages) {
            if (err.containsIgnoreCase('binding') || err.containsIgnoreCase('colon')) {
                hasBindingError = true;
                break;
            }
        }
        System.assert(hasBindingError,
            'Should report binding variable error. Errors: ' +
            String.join(result.errorMessages, ', '));
    }

    // -------------------------------------------------------------------------
    // Multi-failure: all errors collected (not just first)
    // -------------------------------------------------------------------------

    @isTest
    static void validate_multipleFailures_allErrorsCollected() {
        // Query with DML keyword AND no LIMIT clause — should produce at least 2 errors
        ValidationResult result = ChecklistQueryValidator.validate(
            'DELETE FROM User'
        );
        System.assertEquals(false, result.isValid,
            'Query with multiple violations should be invalid');
        System.assert(result.errorMessages.size() >= 2,
            'Should collect all errors, not just first. Error count: ' +
            result.errorMessages.size() + ', errors: ' +
            String.join(result.errorMessages, '; '));
    }
}
