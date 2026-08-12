import { describe, it, expect } from 'vitest';
import { formatResults } from '../../src/validate/formatResults';

describe('formatResults', () => {
  it('returns a PASS summary for a valid result', () => {
    const result = { valid: true, errors: [] };
    const output = formatResults('fixtures/valid-custom-object.xml', result);
    expect(output).toContain('PASS:');
    expect(output).toContain('fixtures/valid-custom-object.xml');
    expect(output).toContain('0 errors');
    expect(output).toContain('is valid');
  });

  it('returns a FAIL summary with per-error details for an invalid result', () => {
    const result = {
      valid: false,
      errors: [
        { message: "Element 'fullNam': This element is not expected.", line: 4, column: 5 },
        { message: "Element 'deploymentStatus': 'Active' is not a valid value.", line: 8, column: 5 },
      ],
    };
    const output = formatResults('fixtures/invalid-custom-object.xml', result);
    expect(output).toContain('FAIL:');
    expect(output).toContain('fixtures/invalid-custom-object.xml');
    expect(output).toContain('2 error(s)');
    expect(output).toContain('Line 4, Col 5:');
    expect(output).toContain("Element 'fullNam'");
    expect(output).toContain('Line 8, Col 5:');
    expect(output).toContain("'Active' is not a valid value");
  });
});
