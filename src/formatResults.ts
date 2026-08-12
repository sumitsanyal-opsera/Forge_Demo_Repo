import type { ValidationResult } from './types';

export function formatResults(result: ValidationResult): string {
  if (result.isValid) {
    return 'Validation passed: no errors found';
  }
  const lines = result.errors.map((e) => `Line ${e.line}: ${e.message}`);
  return lines.join('\n');
}
