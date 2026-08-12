import { describe, it, expect } from 'vitest';
import { formatResults } from '../index';
import type { FileValidationResult } from '../validate';

describe('formatResults', () => {
  it('shows correct passed count and no FAIL lines when all files pass', () => {
    const results: FileValidationResult[] = [
      { filePath: 'a.xml', valid: true, errors: [] },
      { filePath: 'b.xml', valid: true, errors: [] },
    ];
    const output = formatResults(results);
    expect(output).toContain('2 passed');
    expect(output).toContain('0 failed');
    expect(output).toContain('out of 2 files');
    expect(output).not.toContain('FAIL');
  });

  it('shows file path, line number, and message for a failing result', () => {
    const results: FileValidationResult[] = [
      {
        filePath: 'bad.xml',
        valid: false,
        errors: [{ line: 5, message: 'Element bogus not expected' }],
      },
    ];
    const output = formatResults(results);
    expect(output).toContain('FAIL');
    expect(output).toContain('bad.xml');
    expect(output).toContain('Line 5');
    expect(output).toContain('Element bogus not expected');
    expect(output).toContain('0 passed');
    expect(output).toContain('1 failed');
  });

  it('shows correct pass/fail counts for mixed results', () => {
    const results: FileValidationResult[] = [
      { filePath: 'good.xml', valid: true, errors: [] },
      {
        filePath: 'bad.xml',
        valid: false,
        errors: [{ line: 3, message: 'Missing required element' }],
      },
    ];
    const output = formatResults(results);
    expect(output).toContain('1 passed');
    expect(output).toContain('1 failed');
    expect(output).toContain('out of 2 files');
    expect(output).toContain('PASS');
    expect(output).toContain('FAIL');
  });
});
