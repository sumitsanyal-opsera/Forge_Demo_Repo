import { describe, it, expect } from 'vitest';
import * as path from 'path';
import { validateXml } from '../src/validate';

const FIXTURES_DIR = path.resolve(__dirname, '../fixtures');

describe('validateXml smoke test', () => {
  it('is importable and returns isValid: true for valid XML and matching XSD', () => {
    const result = validateXml(
      path.join(FIXTURES_DIR, 'valid-custom-object.xml'),
      path.join(FIXTURES_DIR, 'custom-object.xsd')
    );
    expect(result.isValid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });
});
