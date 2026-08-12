import * as fs from 'fs';
import * as path from 'path';
import * as libxmljs from 'libxmljs2';
import { validateMetadataXml, ValidationResult as BatchValidationResult } from './validator';
import { validateXmlAgainstXsd } from './validateXml';
import { formatResults as formatSingleResult } from './formatResults';
import type { ValidationResult as SingleValidationResult } from './types';

const BATCH_XSD_PATH = path.resolve(__dirname, '..', 'test', 'fixtures', 'schemas', 'metadata-61.0.xsd');
const BUNDLED_SCHEMA_PATH = path.resolve(__dirname, '..', 'schemas', 'metadata.xsd');

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

export function formatResults(results: BatchValidationResult[]): string {
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

function validateFile(filePath: string): void {
  let xmlContent: string;
  try {
    xmlContent = fs.readFileSync(filePath, 'utf-8');
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(`Error: Could not read file ${filePath}: ${msg}\n`);
    process.exit(1);
  }

  let xsdContent: string;
  try {
    xsdContent = fs.readFileSync(BUNDLED_SCHEMA_PATH, 'utf-8');
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(`Error: Could not load bundled schema: ${msg}\n`);
    process.exit(1);
  }

  const errors = validateXmlAgainstXsd(xmlContent, xsdContent);
  const result: SingleValidationResult = {
    isValid: errors.length === 0,
    errors: errors.map((e) => ({ line: e.line, column: e.column, message: e.message })),
  };

  const output = formatSingleResult(result);
  if (result.isValid) {
    console.log(output);
  } else {
    process.stderr.write(output + '\n');
    process.exitCode = 1;
  }
}

function validateDirectory(dirPath: string): void {
  if (!fs.existsSync(BATCH_XSD_PATH)) {
    console.error(`Error: XSD schema not found at ${BATCH_XSD_PATH}`);
    process.exit(1);
  }

  const xmlFiles = discoverXmlFiles(dirPath);

  if (xmlFiles.length === 0) {
    console.log('Validation passed: 0 files found');
    process.exit(0);
  }

  const xsdContent = fs.readFileSync(BATCH_XSD_PATH, 'utf-8');
  const schema = libxmljs.parseXml(xsdContent);

  const results: BatchValidationResult[] = xmlFiles.map((f) => validateMetadataXml(f, schema));
  const output = formatResults(results);
  console.log(output);

  if (results.some((r) => !r.isValid)) {
    process.exitCode = 1;
  }
}

function main(): void {
  const targetPath = process.argv[2];

  if (!targetPath) {
    process.stderr.write('Usage: npx ts-node src/cli.ts <file.xml>\n');
    process.exit(1);
  }

  if (!fs.existsSync(targetPath)) {
    process.stderr.write(`Error: File not found: ${targetPath}\n`);
    process.exit(1);
  }

  const stat = fs.statSync(targetPath);
  if (stat.isDirectory()) {
    validateDirectory(targetPath);
  } else {
    validateFile(targetPath);
  }
}

main();
