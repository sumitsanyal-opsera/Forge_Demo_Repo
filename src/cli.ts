import * as fs from 'fs';
import * as path from 'path';
import * as libxmljs from 'libxmljs2';
import { validateMetadataXml, ValidationResult } from './validator';

const XSD_PATH = path.resolve(__dirname, '..', 'test', 'fixtures', 'schemas', 'metadata-61.0.xsd');

export function discoverXmlFiles(dirPath: string): string[] {
  const results: string[] = [];
  for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
    const fullPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      results.push(...discoverXmlFiles(fullPath));
    } else if (entry.isFile() && entry.name.endsWith('.xml')) {
      results.push(fullPath);
    }
  }
  return results;
}

export function formatResults(results: ValidationResult[]): string {
  const lines: string[] = [];
  let errorCount = 0;

  for (const result of results) {
    if (result.isValid) {
      lines.push(`PASS: ${result.filePath}`);
    } else {
      lines.push(`FAIL: ${result.filePath}`);
      for (const err of result.errors) {
        lines.push(`  ${err}`);
      }
      errorCount += result.errors.length;
    }
  }

  const total = results.length;
  if (errorCount === 0) {
    lines.push(`Validation passed: ${total} files validated, 0 errors`);
  } else {
    lines.push(`Validation failed: ${total} files validated, ${errorCount} errors`);
  }

  return lines.join('\n');
}

function main(): void {
  const dirPath = process.argv[2];

  if (!dirPath) {
    console.error('Usage: tsx src/cli.ts <directory>');
    process.exit(2);
  }

  if (!fs.existsSync(dirPath)) {
    console.error(`Error: Directory not found: ${dirPath}`);
    process.exit(2);
  }

  if (!fs.existsSync(XSD_PATH)) {
    console.error(`Error: XSD schema not found at ${XSD_PATH}`);
    process.exit(2);
  }

  const xmlFiles = discoverXmlFiles(dirPath);

  if (xmlFiles.length === 0) {
    console.log('Validation passed: 0 files found');
    process.exit(0);
  }

  const xsdContent = fs.readFileSync(XSD_PATH, 'utf-8');
  const schema = libxmljs.parseXml(xsdContent);

  const results: ValidationResult[] = xmlFiles.map((f) => validateMetadataXml(f, schema));
  const output = formatResults(results);
  console.log(output);

  if (results.some((r) => !r.isValid)) {
    process.exitCode = 1;
  }
}

main();
