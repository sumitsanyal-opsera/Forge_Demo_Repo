import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { validateMetadataXml } from './validator';

const FIXTURES_DIR = path.resolve(__dirname, '..', 'test', 'fixtures');
const SCHEMAS_DIR = path.join(FIXTURES_DIR, 'schemas');
const XSD_PATH = path.join(SCHEMAS_DIR, 'metadata-61.0.xsd');

describe('validateMetadataXml', () => {
  it('returns valid:true and empty errors array for well-formed XML conforming to XSD', () => {
    const xmlContent = fs.readFileSync(
      path.join(FIXTURES_DIR, 'valid', 'objects', 'Account.object-meta.xml'),
      'utf-8'
    );
    const xsdContent = fs.readFileSync(XSD_PATH, 'utf-8');
    const result = validateMetadataXml(xmlContent, xsdContent, 'Account.object-meta.xml');
    expect(result.valid).toBe(true);
    expect(result.errors).toHaveLength(0);
    expect(result.filePath).toBe('Account.object-meta.xml');
  });

  it('returns valid:false with phase xsd errors for XML that violates the XSD', () => {
    const xmlContent = fs.readFileSync(
      path.join(FIXTURES_DIR, 'invalid', 'InvalidObject.object-meta.xml'),
      'utf-8'
    );
    const xsdContent = fs.readFileSync(XSD_PATH, 'utf-8');
    const result = validateMetadataXml(xmlContent, xsdContent, 'InvalidObject.object-meta.xml');
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0].phase).toBe('xsd');
    expect(result.errors[0].line).toBeGreaterThan(0);
    expect(result.errors[0].message).toContain('bogusElement');
  });

  it('returns valid:false with wellformedness phase for malformed XML, not attempting XSD validation', () => {
    const result = validateMetadataXml('<root><unclosed>', '<schema/>', 'malformed.xml');
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0].phase).toBe('wellformedness');
    expect(result.errors.every((e) => e.phase === 'wellformedness')).toBe(true);
  });

  it('returns valid:false with wellformedness error for empty XML input', () => {
    const xsdContent = fs.readFileSync(XSD_PATH, 'utf-8');
    const result = validateMetadataXml('', xsdContent, 'empty.xml');
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0].phase).toBe('wellformedness');
  });
});
