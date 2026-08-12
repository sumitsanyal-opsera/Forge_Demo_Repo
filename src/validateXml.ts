import * as libxmljs from 'libxmljs2';
import type { ValidationResult } from './types';

export function validateXml(xmlContent: string, xsdDoc: libxmljs.Document): ValidationResult {
  if (!xmlContent) {
    return {
      isValid: false,
      errors: [{ line: 0, column: 0, message: 'XML content is empty' }],
    };
  }

  let xmlDoc: libxmljs.Document;
  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    xmlDoc = libxmljs.parseXml(xmlContent, { noent: false, nonet: true } as any);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return {
      isValid: false,
      errors: [{ line: 0, column: 0, message: `XML parse error: ${msg}` }],
    };
  }

  const isValid = xmlDoc.validate(xsdDoc);
  const errors = xmlDoc.validationErrors.map((e) => ({
    line: e.line,
    column: e.column,
    message: e.message.trim(),
  }));

  return { isValid, errors };
}
