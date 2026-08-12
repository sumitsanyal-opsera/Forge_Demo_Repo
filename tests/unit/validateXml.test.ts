import { describe, it, expect, beforeAll } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import * as libxmljs from 'libxmljs2';
import { validateXml } from '../../src/validateXml';

const FIXTURES_DIR = path.resolve(__dirname, '../fixtures');
const SCHEMAS_DIR = path.resolve(__dirname, '../../schemas');

describe('validateXml', () => {
  let xsdDoc: libxmljs.Document;

  beforeAll(() => {
    const xsdContent = fs.readFileSync(path.join(SCHEMAS_DIR, 'metadata.xsd'), 'utf-8');
    xsdDoc = libxmljs.parseXml(xsdContent);
  });

  it('returns isValid: true and empty errors for valid metadata XML', () => {
    const xmlContent = fs.readFileSync(
      path.join(FIXTURES_DIR, 'valid-metadata.xml'),
      'utf-8'
    );
    const result = validateXml(xmlContent, xsdDoc);
    expect(result.isValid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  it('returns isValid: false with errors for XML with schema violations', () => {
    const xmlContent = fs.readFileSync(
      path.join(FIXTURES_DIR, 'invalid-metadata.xml'),
      'utf-8'
    );
    const result = validateXml(xmlContent, xsdDoc);
    expect(result.isValid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]).toMatchObject({
      line: expect.any(Number),
      column: expect.any(Number),
      message: expect.any(String),
    });
  });

  it('returns isValid: false with a parse error for malformed XML', () => {
    const result = validateXml('<root><unclosed>', xsdDoc);
    expect(result.isValid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0].message).toMatch(/parse error/i);
  });

  it('returns isValid: false with a descriptive error for an empty string', () => {
    const result = validateXml('', xsdDoc);
    expect(result.isValid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0].message).toMatch(/empty/i);
  });
});
