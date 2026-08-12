import * as fs from 'fs';
import * as libxmljs from 'libxmljs2';

export interface XmlError {
  message: string;
  line: number;
  column: number;
}

export interface XmlParseResult {
  valid: boolean;
  errors: XmlError[];
}

export function parseXml(xmlPath: string): XmlParseResult {
  let content: string;
  try {
    content = fs.readFileSync(xmlPath, 'utf-8');
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { valid: false, errors: [{ message: msg, line: 0, column: 0 }] };
  }

  try {
    libxmljs.parseXml(content);
    return { valid: true, errors: [] };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { valid: false, errors: [{ message: msg, line: 0, column: 0 }] };
  }
}
