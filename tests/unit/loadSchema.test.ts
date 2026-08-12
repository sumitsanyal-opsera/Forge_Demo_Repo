import { describe, it, expect } from 'vitest';
import * as path from 'path';
import { loadSchema } from '../../src/loadSchema';

const FIXTURES_DIR = path.resolve(__dirname, '../fixtures');
const SCHEMAS_DIR = path.resolve(__dirname, '../../schemas');

describe('loadSchema', () => {
  it('loads and parses a valid XSD file, returning a Document', () => {
    const doc = loadSchema(path.join(SCHEMAS_DIR, 'metadata.xsd'));
    expect(doc).toBeDefined();
    expect(typeof doc.validate).toBe('function');
  });

  it('uses the default path (schemas/metadata.xsd) when no argument is given', () => {
    const doc = loadSchema();
    expect(doc).toBeDefined();
  });

  it('throws a descriptive error when the file does not exist', () => {
    const badPath = path.join(FIXTURES_DIR, 'nonexistent.xsd');
    expect(() => loadSchema(badPath)).toThrow(badPath);
  });

  it('throws a parse error when the XSD content is malformed XML', () => {
    const malformedPath = path.join(FIXTURES_DIR, 'malformed.xsd');
    expect(() => loadSchema(malformedPath)).toThrow(/parse/i);
  });
});
