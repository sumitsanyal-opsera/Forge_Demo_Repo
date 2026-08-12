import * as fs from 'fs';
import * as path from 'path';
import * as libxmljs from 'libxmljs2';

const DEFAULT_SCHEMA_PATH = path.join(__dirname, '..', 'schemas', 'metadata.xsd');

export function loadSchema(filePath: string = DEFAULT_SCHEMA_PATH): libxmljs.Document {
  let content: string;
  try {
    content = fs.readFileSync(filePath, 'utf-8');
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to load XSD schema from ${filePath}: ${msg}`);
  }

  try {
    return libxmljs.parseXml(content);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to parse XSD schema at ${filePath}: ${msg}`);
  }
}
