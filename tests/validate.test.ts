import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { validateXml } from '../src/validate';

const FIXTURES_DIR = path.resolve(__dirname, '../fixtures');
const XSD_PATH = path.join(FIXTURES_DIR, 'testMetadata.xsd');

function readFixture(name: string): string {
  return fs.readFileSync(path.join(FIXTURES_DIR, name), 'utf-8');
}

describe('validateXml', () => {
  it('returns valid:true for XML that conforms to the XSD', () => {
    const result = validateXml(
      readFixture('validAccount.object-meta.xml'),
      readFixture('testMetadata.xsd'),
    );
    expect(result.valid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  it('returns valid:false with parse error for malformed XML', () => {
    const result = validateXml(
      readFixture('malformed.xml'),
      readFixture('testMetadata.xsd'),
    );
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]).toBeTruthy();
  });

  it('returns valid:false with schema error for well-formed XML with invalid element', () => {
    const result = validateXml(
      readFixture('invalidProfile.profile-meta.xml'),
      readFixture('testMetadata.xsd'),
    );
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]).toMatch(/unknownElement|Line \d+/);
  });
});
