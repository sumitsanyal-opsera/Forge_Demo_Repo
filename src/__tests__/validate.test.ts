import { describe, it, expect } from 'vitest';
import * as path from 'path';
import { loadSchema, validateFiles } from '../validate';

const SCHEMAS_DIR = path.resolve(__dirname, '../../schemas');
const TEST_DATA_DIR = path.resolve(__dirname, '../../test-data');
const XSD_PATH = path.join(SCHEMAS_DIR, 'CustomObject.xsd');
const VALID_XML = path.join(TEST_DATA_DIR, 'valid.object-meta.xml');
const INVALID_XML = path.join(TEST_DATA_DIR, 'invalid.object-meta.xml');

describe('loadSchema', () => {
  it('returns a Document with a non-null root element for a valid XSD', () => {
    const doc = loadSchema(XSD_PATH);
    expect(doc).toBeDefined();
    expect(doc.root()).not.toBeNull();
  });

  it('throws a descriptive error containing the file path for a missing file', () => {
    const missingPath = path.join(SCHEMAS_DIR, 'nonexistent.xsd');
    expect(() => loadSchema(missingPath)).toThrowError(missingPath);
  });
});

describe('validateFiles', () => {
  it('returns valid:true and empty errors for a conforming XML file', () => {
    const schema = loadSchema(XSD_PATH);
    const results = validateFiles(schema, [VALID_XML]);
    expect(results).toHaveLength(1);
    expect(results[0].valid).toBe(true);
    expect(results[0].errors).toHaveLength(0);
    expect(results[0].filePath).toBe(VALID_XML);
  });

  it('returns valid:false with errors for an XSD-violating XML file', () => {
    const schema = loadSchema(XSD_PATH);
    const results = validateFiles(schema, [INVALID_XML]);
    expect(results).toHaveLength(1);
    expect(results[0].valid).toBe(false);
    expect(results[0].errors.length).toBeGreaterThan(0);
    expect(results[0].errors[0].line).toBeTypeOf('number');
    expect(results[0].errors[0].message).toBeTruthy();
  });

  it('returns one result per file when validating multiple files', () => {
    const schema = loadSchema(XSD_PATH);
    const results = validateFiles(schema, [VALID_XML, INVALID_XML]);
    expect(results).toHaveLength(2);
    expect(results[0].valid).toBe(true);
    expect(results[1].valid).toBe(false);
  });

  it('returns valid:false with a descriptive error for a nonexistent file path', () => {
    const schema = loadSchema(XSD_PATH);
    const missingXml = path.join(TEST_DATA_DIR, 'does-not-exist.xml');
    const results = validateFiles(schema, [missingXml]);
    expect(results).toHaveLength(1);
    expect(results[0].valid).toBe(false);
    expect(results[0].errors[0].message).toContain(missingXml);
  });
});
