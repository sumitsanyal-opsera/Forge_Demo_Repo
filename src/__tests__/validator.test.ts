import { describe, it, expect } from 'vitest';
import * as path from 'path';
import { validateXmlAgainstXsd } from '../validator';

const FIXTURES_DIR = path.resolve(__dirname, '../../test/fixtures');
const XSD_PATH = path.join(FIXTURES_DIR, 'salesforce-custom-object.xsd');

describe('validateXmlAgainstXsd', () => {
  it('returns isValid:true and empty errors for valid XML against matching XSD', async () => {
    const result = await validateXmlAgainstXsd(
      path.join(FIXTURES_DIR, 'valid-custom-object.xml'),
      XSD_PATH,
    );
    expect(result.isValid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  it('returns isValid:false with descriptive error for XML with unknown element', async () => {
    const result = await validateXmlAgainstXsd(
      path.join(FIXTURES_DIR, 'invalid-unknown-element.xml'),
      XSD_PATH,
    );
    expect(result.isValid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]).toBeTruthy();
  });

  it('returns isValid:false with descriptive error for XML missing required element', async () => {
    const result = await validateXmlAgainstXsd(
      path.join(FIXTURES_DIR, 'invalid-missing-required.xml'),
      XSD_PATH,
    );
    expect(result.isValid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]).toBeTruthy();
  });
});
