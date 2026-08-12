import * as fs from 'fs';
import * as path from 'path';
import * as libxmljs from 'libxmljs2';

const DEFAULT_SCHEMA_PATH = path.join(__dirname, '..', 'schemas', 'CustomObject.xsd');

// WO-093: structured result for validateFiles
export interface FileValidationResult {
  filePath: string;
  valid: boolean;
  errors: Array<{ line: number; message: string }>;
}

export function loadSchema(xsdPath: string = DEFAULT_SCHEMA_PATH): libxmljs.Document {
  let content: string;
  try {
    content = fs.readFileSync(xsdPath, 'utf-8');
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to load XSD schema from ${xsdPath}: ${msg}`);
  }
  try {
    return libxmljs.parseXml(content);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to parse XSD schema at ${xsdPath}: ${msg}`);
  }
}

export function validateFiles(
  schema: libxmljs.Document,
  xmlPaths: string[],
): FileValidationResult[] {
  return xmlPaths.map((xmlPath) => {
    let xmlContent: string;
    try {
      xmlContent = fs.readFileSync(xmlPath, 'utf-8');
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      return {
        filePath: xmlPath,
        valid: false,
        errors: [{ line: 0, message: `Cannot read file ${xmlPath}: ${msg}` }],
      };
    }

    let xmlDoc: libxmljs.Document;
    try {
      xmlDoc = libxmljs.parseXml(xmlContent);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      return {
        filePath: xmlPath,
        valid: false,
        errors: [{ line: 0, message: `XML parse error: ${msg}` }],
      };
    }

    xmlDoc.validate(schema);
    const errors = xmlDoc.validationErrors.map((e) => ({
      line: e.line ?? 0,
      message: e.message.trim(),
    }));
    return { filePath: xmlPath, valid: errors.length === 0, errors };
  });
}

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
