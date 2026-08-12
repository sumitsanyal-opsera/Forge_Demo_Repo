import { describe, it, expect, beforeAll } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { validateXml, validateXmlAgainstXsd } from '../src/validateXml';

const FIXTURES_DIR = path.resolve(__dirname, 'fixtures');

function readFixture(name: string): string {
  return fs.readFileSync(path.join(FIXTURES_DIR, name), 'utf-8');
}

describe('validateXml - Phase 1 (well-formedness)', () => {
  it('returns empty array for well-formed valid XML', () => {
    const results = validateXml(readFixture('valid.xml'));
    expect(results).toHaveLength(0);
  });

  it('returns wellformedness error with line number for unclosed tag', () => {
    const results = validateXml(readFixture('unclosed-tag.xml'));
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].phase).toBe('wellformedness');
    expect(results[0].line).toBeGreaterThan(0);
    expect(results[0].message).toBeTruthy();
    expect(results[0].xsdRule).toBeNull();
  });

  it('returns wellformedness error for XML with invalid control characters', () => {
    const results = validateXml(readFixture('invalid-chars.xml'));
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].phase).toBe('wellformedness');
  });

  it('returns descriptive error for empty string without throwing', () => {
    const results = validateXml('');
    expect(results).toHaveLength(1);
    expect(results[0].message).toMatch(/empty/i);
    expect(results[0].phase).toBe('wellformedness');
    expect(results[0].xsdRule).toBeNull();
  });
});

describe('validateXmlAgainstXsd - Phase 2 (schema validation)', () => {
  let xsdContent: string;

  beforeAll(() => {
    xsdContent = readFixture('test-metadata.xsd');
  });

  it('returns empty array for XML conforming to the XSD', () => {
    const results = validateXmlAgainstXsd(readFixture('valid.xml'), xsdContent);
    expect(results).toHaveLength(0);
  });

  it('returns xsd-phase errors for XML with unexpected element', () => {
    const results = validateXmlAgainstXsd(readFixture('unexpected-element.xml'), xsdContent);
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].phase).toBe('xsd');
    expect(results[0].message).toBeTruthy();
  });

  it('returns xsd-phase errors for XML missing required apiVersion', () => {
    const results = validateXmlAgainstXsd(readFixture('missing-required.xml'), xsdContent);
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].phase).toBe('xsd');
  });

  it('returns only wellformedness errors for malformed XML, never running XSD phase', () => {
    const results = validateXmlAgainstXsd(readFixture('unclosed-tag.xml'), xsdContent);
    expect(results.length).toBeGreaterThan(0);
    expect(results.every((r) => r.phase === 'wellformedness')).toBe(true);
  });

  it('returns descriptive xsd-phase error for malformed XSD without throwing', () => {
    const malformedXsd = '<?xml version="1.0"?><xs:schema><unclosed>';
    const results = validateXmlAgainstXsd(readFixture('valid.xml'), malformedXsd);
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].phase).toBe('xsd');
    expect(results[0].message).toMatch(/schema/i);
  });
});
