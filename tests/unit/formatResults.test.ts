import { describe, it, expect } from 'vitest';
import { formatResults } from '../../src/formatResults';

describe('formatResults', () => {
  it('returns success message for a valid result', () => {
    const result = { isValid: true, errors: [] };
    expect(formatResults(result)).toBe('Validation passed: no errors found');
  });

  it('returns formatted error lines for an invalid result', () => {
    const result = {
      isValid: false,
      errors: [
        { line: 3, column: 1, message: 'Element is not allowed here' },
        { line: 7, column: 5, message: 'Missing required element' },
      ],
    };
    const output = formatResults(result);
    expect(output).toContain('Line 3: Element is not allowed here');
    expect(output).toContain('Line 7: Missing required element');
  });

  it('returns a single error line for a single error', () => {
    const result = {
      isValid: false,
      errors: [{ line: 1, column: 0, message: 'Input is empty' }],
    };
    expect(formatResults(result)).toBe('Line 1: Input is empty');
  });

  it('returns success message when isValid is true with empty errors', () => {
    const result = { isValid: true, errors: [] };
    const output = formatResults(result);
    expect(output).toMatch(/passed/i);
  });
});
