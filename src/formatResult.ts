import type { ValidationResult } from './validateXml';

export function formatResult(result: ValidationResult, filePath: string): string {
  let line = `${filePath}:${result.line}:${result.column} [${result.phase}] ${result.message}`;
  if (result.xsdRule) {
    line += ` (rule: ${result.xsdRule})`;
  }
  return line;
}
