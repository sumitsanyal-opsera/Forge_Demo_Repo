import * as fs from 'fs';
import * as libxmljs from 'libxmljs2';

export interface XsdValidationError {
  message: string;
  line: number;
  column: number;
}

export interface XsdValidationResult {
  valid: boolean;
  errors: XsdValidationError[];
}

export function validateAgainstXsd(xmlString: string, xsdPath: string): XsdValidationResult {
  let xsdContent: string;
  try {
    xsdContent = fs.readFileSync(xsdPath, 'utf-8');
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { valid: false, errors: [{ message: `Cannot read XSD file: ${msg}`, line: 0, column: 0 }] };
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
    xmlDoc = libxmljs.parseXml(xmlString);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { valid: false, errors: [{ message: `XML parse error: ${msg}`, line: 0, column: 0 }] };
  }

  xmlDoc.validate(xsdDoc);
  const errors: XsdValidationError[] = xmlDoc.validationErrors.map((e) => ({
    message: e.message.trim(),
    line: e.line,
    column: e.column,
  }));

  return { valid: errors.length === 0, errors };
}
