import { describe, it, expect } from 'vitest';
import * as path from 'path';
import { loadAndParseXml } from '../parser';
import { FileNotFoundError, XmlParseError } from '../errors';

const FIXTURES_DIR = path.resolve(__dirname, '../../test/fixtures');

describe('loadAndParseXml', () => {
  it('returns a parsed object with CustomObject root element for valid XML', async () => {
    const result = await loadAndParseXml(path.join(FIXTURES_DIR, 'valid-custom-object.xml'));
    expect(result).toHaveProperty('CustomObject');
  });

  it('throws FileNotFoundError including the file path for a missing file', async () => {
    const missingPath = path.join(FIXTURES_DIR, 'does-not-exist.xml');
    await expect(loadAndParseXml(missingPath)).rejects.toThrow(FileNotFoundError);
    await expect(loadAndParseXml(missingPath)).rejects.toThrow(missingPath);
  });

  it('throws XmlParseError for malformed XML', async () => {
    await expect(
      loadAndParseXml(path.join(FIXTURES_DIR, 'malformed.xml')),
    ).rejects.toThrow(XmlParseError);
  });
});
