import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { discoverXmlFiles, formatResults } from './cli';
import type { ValidationResult } from './validator';

describe('discoverXmlFiles', () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'cli-test-'));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('finds .xml files in a flat directory', () => {
    fs.writeFileSync(path.join(tmpDir, 'a.xml'), '<a/>');
    fs.writeFileSync(path.join(tmpDir, 'b.xml'), '<b/>');
    fs.writeFileSync(path.join(tmpDir, 'c.txt'), 'not xml');

    const files = discoverXmlFiles(tmpDir);
    expect(files).toHaveLength(2);
    expect(files.some((f) => f.endsWith('a.xml'))).toBe(true);
    expect(files.some((f) => f.endsWith('b.xml'))).toBe(true);
  });

  it('finds .xml files recursively in nested directories', () => {
    const subDir = path.join(tmpDir, 'sub');
    fs.mkdirSync(subDir);
    fs.writeFileSync(path.join(tmpDir, 'root.xml'), '<r/>');
    fs.writeFileSync(path.join(subDir, 'nested.xml'), '<n/>');

    const files = discoverXmlFiles(tmpDir);
    expect(files).toHaveLength(2);
    expect(files.some((f) => f.endsWith('root.xml'))).toBe(true);
    expect(files.some((f) => f.endsWith('nested.xml'))).toBe(true);
  });

  it('returns empty array for a directory with no xml files', () => {
    const files = discoverXmlFiles(tmpDir);
    expect(files).toHaveLength(0);
  });
});

describe('formatResults', () => {
  it('formats a passing result with the summary line', () => {
    const results: ValidationResult[] = [
      { filePath: 'a.xml', isValid: true, errors: [] },
    ];
    const output = formatResults(results);
    expect(output).toContain('PASS: a.xml');
    expect(output).toContain('Validation passed: 1 files validated, 0 errors');
  });

  it('formats a failing result with indented error details', () => {
    const results: ValidationResult[] = [
      { filePath: 'b.xml', isValid: false, errors: ['Line 6: bad element'] },
    ];
    const output = formatResults(results);
    expect(output).toContain('FAIL: b.xml');
    expect(output).toContain('  Line 6: bad element');
    expect(output).toContain('Validation failed: 1 files validated, 1 errors');
  });

  it('handles mixed valid and invalid results', () => {
    const results: ValidationResult[] = [
      { filePath: 'a.xml', isValid: true, errors: [] },
      { filePath: 'b.xml', isValid: false, errors: ['Line 3: error one', 'Line 5: error two'] },
    ];
    const output = formatResults(results);
    expect(output).toContain('PASS: a.xml');
    expect(output).toContain('FAIL: b.xml');
    expect(output).toContain('Validation failed: 2 files validated, 2 errors');
  });
});
