import * as libxmljs from 'libxmljs2';
import { validateXml as validateXmlFromPath } from './xml-validator';

// WO-097: structured error with phase discrimination
export interface ValidationError {
  line: number;
  column: number;
  message: string;
  phase: 'wellformedness' | 'xsd';
}

// WO-097: primary ValidationResult type
export interface ValidationResult {
  filePath: string;
  valid: boolean;
  errors: ValidationError[];
}

// Legacy type retained for the batch directory scanner (WO-087)
export interface BatchValidationResult {
  filePath: string;
  isValid: boolean;
  errors: string[];
}

function extractParseError(err: unknown): ValidationError {
  const msg = err instanceof Error ? err.message : String(err);
  const lineMatch = msg.match(/line[:\s]+(\d+)/i);
  const colMatch = msg.match(/col(?:umn)?[:\s]+(\d+)/i);
  return {
    line: lineMatch ? parseInt(lineMatch[1], 10) : 0,
    column: colMatch ? parseInt(colMatch[1], 10) : 0,
    message: msg.trim(),
    phase: 'wellformedness',
  };
}

/**
 * Two-phase validation: Phase 1 checks well-formedness, Phase 2 checks XSD conformance.
 * Short-circuits after Phase 1 if the XML is not well-formed.
 */
export function validateMetadataXml(
  xmlContent: string,
  xsdContent: string,
  filePath: string,
): ValidationResult {
  // Phase 1: well-formedness
  let xmlDoc: libxmljs.Document;
  try {
    xmlDoc = libxmljs.parseXml(xmlContent);
  } catch (err: unknown) {
    return { filePath, valid: false, errors: [extractParseError(err)] };
  }

  // Phase 2: XSD conformance
  const xsdDoc = libxmljs.parseXml(xsdContent);
  xmlDoc.validate(xsdDoc);

  const errors: ValidationError[] = xmlDoc.validationErrors.map((e) => ({
    line: e.line,
    column: e.column,
    message: e.message.trim(),
    phase: 'xsd' as const,
  }));

  return { filePath, valid: errors.length === 0, errors };
}

// Legacy function for the batch directory scanner — accepts a file path and pre-parsed schema
export function validateMetadataXmlLegacy(
  xmlPath: string,
  schema: libxmljs.Document,
): BatchValidationResult {
  const result = validateXmlFromPath(xmlPath, schema);
  return { filePath: xmlPath, ...result };
}
