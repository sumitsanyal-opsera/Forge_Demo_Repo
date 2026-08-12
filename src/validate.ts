import * as fs from 'fs';
import * as libxmljs from 'libxmljs2';

export interface ValidationError {
  message: string;
  line: number | null;
}

export interface ValidationResult {
  filePath: string;
  isValid: boolean;
  errors: ValidationError[];
}

export function validateXml(xmlPath: string, xsdPath: string): ValidationResult {
  let xsdContent: string;
  try {
    xsdContent = fs.readFileSync(xsdPath, 'utf-8');
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { filePath: xmlPath, isValid: false, errors: [{ message: `Cannot read XSD: ${msg}`, line: null }] };
  }

  let xmlContent: string;
  try {
    xmlContent = fs.readFileSync(xmlPath, 'utf-8');
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { filePath: xmlPath, isValid: false, errors: [{ message: `Cannot read XML: ${msg}`, line: null }] };
  }

  let xsdDoc: libxmljs.Document;
  try {
    xsdDoc = libxmljs.parseXml(xsdContent);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { filePath: xmlPath, isValid: false, errors: [{ message: `XSD parse error: ${msg}`, line: null }] };
  }

  let xmlDoc: libxmljs.Document;
  try {
    xmlDoc = libxmljs.parseXml(xmlContent);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { filePath: xmlPath, isValid: false, errors: [{ message: `XML parse error: ${msg}`, line: null }] };
  }

  const isValid = xmlDoc.validate(xsdDoc);
  const errors: ValidationError[] = xmlDoc.validationErrors.map((e) => ({
    message: e.message.trim(),
    line: e.line ?? null,
  }));

  return { filePath: xmlPath, isValid, errors };
}
