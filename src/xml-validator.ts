import * as fs from 'fs';
import * as libxmljs from 'libxmljs2';

export interface ValidationResult {
  isValid: boolean;
  errors: string[];
}

export function validateXml(xmlPath: string, schema: libxmljs.Document): ValidationResult {
  let xmlContent: string;
  try {
    xmlContent = fs.readFileSync(xmlPath, 'utf-8');
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return { isValid: false, errors: [`Failed to read file: ${message}`] };
  }

  let xmlDoc: libxmljs.Document;
  try {
    xmlDoc = libxmljs.parseXml(xmlContent);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return { isValid: false, errors: [`XML parse error: ${message}`] };
  }

  const isValid = xmlDoc.validate(schema);
  const errors = xmlDoc.validationErrors.map(
    (e) => `Line ${e.line}: ${e.message.trim()}`
  );

  return { isValid, errors };
}
