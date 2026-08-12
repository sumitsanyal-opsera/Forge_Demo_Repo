import * as fs from 'fs';
import { parseXml } from './validate/parseXml';
import { validateAgainstXsd } from './validate/validateAgainstXsd';
import { formatResults as formatSingleResult } from './validate/formatResults';
import { loadSchema, validateFiles, FileValidationResult } from './validate';

const GREEN = '\x1b[32m';
const RED = '\x1b[31m';
const RESET = '\x1b[0m';

export function formatResults(results: FileValidationResult[]): string {
  const passed = results.filter((r) => r.valid).length;
  const failed = results.filter((r) => !r.valid).length;
  const total = results.length;
  const lines: string[] = [];

  for (const result of results) {
    if (result.valid) {
      lines.push(`${GREEN}PASS${RESET} ${result.filePath}`);
    } else {
      lines.push(`${RED}FAIL${RESET} ${result.filePath}`);
      for (const err of result.errors) {
        lines.push(`  Line ${err.line}: ${err.message}`);
      }
    }
  }

  lines.push(`Results: ${passed} passed, ${failed} failed out of ${total} files`);
  return lines.join('\n');
}

function main(): void {
  const args = process.argv.slice(2);
  const xsdFlagIdx = args.indexOf('--xsd');

  if (xsdFlagIdx !== -1) {
    // WO-094 mode: --xsd <xsdPath> <xml-files...>
    const xsdPath = args[xsdFlagIdx + 1];
    if (!xsdPath || xsdPath.startsWith('--')) {
      process.stderr.write('Usage: validate --xsd <path> <xml-files...>\n');
      process.exit(2);
    }

    const xmlPaths = args.filter((_, i) => i !== xsdFlagIdx && i !== xsdFlagIdx + 1);
    if (xmlPaths.length === 0) {
      process.stderr.write('Usage: validate --xsd <path> <xml-files...>\n');
      process.exit(2);
    }

    let schema: ReturnType<typeof loadSchema>;
    try {
      schema = loadSchema(xsdPath);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      process.stderr.write(`Error: ${msg}\n`);
      process.exit(1);
    }

    const results = validateFiles(schema, xmlPaths);
    console.log(formatResults(results));
    const anyFailed = results.some((r) => !r.valid);
    process.exit(anyFailed ? 1 : 0);
  }

  // WO-090 mode: <xmlFilePath> [xsdFilePath]
  const xmlPath = args[0];
  const xsdPath = args[1];

  if (!xmlPath) {
    process.stderr.write('Usage: ts-node src/index.ts <xmlFilePath> [xsdFilePath]\n');
    process.exit(1);
  }

  if (!fs.existsSync(xmlPath)) {
    process.stderr.write(`Error: File not found: ${xmlPath}\n`);
    process.exit(1);
  }

  if (xsdPath && !fs.existsSync(xsdPath)) {
    process.stderr.write(`Error: XSD file not found: ${xsdPath}\n`);
    process.exit(1);
  }

  const result = xsdPath
    ? validateAgainstXsd(xmlPath, xsdPath)
    : parseXml(xmlPath);

  const output = formatSingleResult(xmlPath, result);
  console.log(output);

  process.exit(result.valid ? 0 : 1);
}

main();
