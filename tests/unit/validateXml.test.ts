import { describe, it, expect, beforeAll } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { validateXml, validateXmlAgainstXsd } from '../../src/validateXml';

const FIXTURES_DIR = path.resolve(__dirname, '../fixtures');
const SCHEMAS_DIR = path.resolve(__dirname, '../../schemas');

describe('validateXml', () => {
  it('returns empty array for well-formed valid XML', () => {
    const xmlContent = fs.readFileSync(path.join(FIXTURES_DIR, 'valid-metadata.xml'), 'utf-8');
    expect(validateXml(xmlContent)).toHaveLength(0);
  });

  it('returns wellformedness error for malformed XML', () => {
    const results = validateXml('<root><unclosed>');
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].phase).toBe('wellformedness');
    expect(results[0].xsdRule).toBeNull();
  });

  it('returns descriptive error for empty string without throwing', () => {
    const results = validateXml('');
    expect(results).toHaveLength(1);
    expect(results[0].message).toMatch(/empty/i);
    expect(results[0].phase).toBe('wellformedness');
  });
});

describe('validateXmlAgainstXsd', () => {
  let xsdContent: string;

  beforeAll(() => {
    xsdContent = fs.readFileSync(path.join(SCHEMAS_DIR, 'metadata.xsd'), 'utf-8');
  });

  it('returns empty array for valid metadata XML conforming to the schema', () => {
    const xmlContent = fs.readFileSync(path.join(FIXTURES_DIR, 'valid-metadata.xml'), 'utf-8');
    expect(validateXmlAgainstXsd(xmlContent, xsdContent)).toHaveLength(0);
  });

  it('returns xsd-phase errors for XML with schema violations', () => {
    const xmlContent = fs.readFileSync(path.join(FIXTURES_DIR, 'invalid-metadata.xml'), 'utf-8');
    const results = validateXmlAgainstXsd(xmlContent, xsdContent);
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].phase).toBe('xsd');
    expect(results[0]).toMatchObject({
      line: expect.any(Number),
      column: expect.any(Number),
      message: expect.any(String),
    });
  });
});
