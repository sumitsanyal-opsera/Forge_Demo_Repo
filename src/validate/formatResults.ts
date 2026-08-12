import type { XmlParseResult } from './parseXml';

export function formatResults(filePath: string, result: XmlParseResult): string {
  if (result.valid) {
    return `PASS: ${filePath} is valid. (0 errors, 0 warnings)`;
  }

  const lines = [`FAIL: ${filePath} has ${result.errors.length} error(s):`];
  for (const err of result.errors) {
    lines.push(`  Line ${err.line}, Col ${err.column}: ${err.message}`);
  }
  return lines.join('\n');
}
