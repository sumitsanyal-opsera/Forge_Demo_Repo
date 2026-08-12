import * as libxmljs from 'libxmljs2';
import { validateXml } from './xml-validator';

export interface ValidationResult {
  filePath: string;
  isValid: boolean;
  errors: string[];
}

export function validateMetadataXml(xmlPath: string, schema: libxmljs.Document): ValidationResult {
  const result = validateXml(xmlPath, schema);
  return { filePath: xmlPath, ...result };
}
