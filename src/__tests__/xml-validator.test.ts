import { describe, it, expect, beforeAll } from 'vitest';
import * as path from 'path';
import * as fs from 'fs';
import * as libxmljs from 'libxmljs2';
import { validateXml } from '../xml-validator';

const FIXTURES_DIR = path.join(__dirname, '../../test-fixtures');

describe('validateXml', () => {
  let schema: libxmljs.Document;

  beforeAll(() => {
    const xsdContent = fs.readFileSync(path.join(FIXTURES_DIR, 'CustomObject.xsd'), 'utf-8');
    schema = libxmljs.parseXml(xsdContent);
  });

  it('returns isValid: true and empty errors for a conforming CustomObject XML', () => {
    const result = validateXml(path.join(FIXTURES_DIR, 'valid-CustomObject.xml'), schema);
    expect(result.isValid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  it('returns isValid: false with descriptive errors for XML with XSD violations', () => {
    const result = validateXml(path.join(FIXTURES_DIR, 'invalid-CustomObject.xml'), schema);
    expect(result.isValid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]).toMatch(/^Line \d+:/);
  });

  it('returns isValid: false with a parse error message for malformed XML', () => {
    const result = validateXml(path.join(FIXTURES_DIR, 'malformed.xml'), schema);
    expect(result.isValid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]).toContain('parse error');
  });
});
