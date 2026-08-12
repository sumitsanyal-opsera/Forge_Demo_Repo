import * as fs from 'fs';
import * as libxmljs from 'libxmljs2';
import type { XmlError, XmlParseResult } from './parseXml';

export function validateAgainstXsd(xmlPath: string, xsdPath: string): XmlParseResult {
  let xsdContent: string;
  try {
    xsdContent = fs.readFileSync(xsdPath, 'utf-8');
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { valid: false, errors: [{ message: `Cannot read XSD: ${msg}`, line: 0, column: 0 }] };
  }

  let xmlContent: string;
  try {
    xmlContent = fs.readFileSync(xmlPath, 'utf-8');
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { valid: false, errors: [{ message: `Cannot read XML: ${msg}`, line: 0, column: 0 }] };
  }

  let xsdDoc: libxmljs.Document;
  try {
    xsdDoc = libxmljs.parseXml(xsdContent);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { valid: false, errors: [{ message: `XSD parse error: ${msg}`, line: 0, column: 0 }] };
  }

  let xmlDoc: libxmljs.Document;
  try {
    xmlDoc = libxmljs.parseXml(xmlContent);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { valid: false, errors: [{ message: `XML parse error: ${msg}`, line: 0, column: 0 }] };
  }

  const isValid = xmlDoc.validate(xsdDoc);
  const errors: XmlError[] = xmlDoc.validationErrors.map((e) => ({
    message: e.message.trim(),
    line: e.line,
    column: e.column,
  }));

  return { valid: isValid, errors };
}
