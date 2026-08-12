import * as path from 'path';
import { validateXmlFile as validateXml, ValidationResult } from './validate';

const FIXTURES_DIR = path.resolve(__dirname, '..', 'fixtures');
const XSD_PATH = path.join(FIXTURES_DIR, 'custom-object.xsd');

const XML_FILES = [
  path.join(FIXTURES_DIR, 'valid-custom-object.xml'),
  path.join(FIXTURES_DIR, 'invalid-custom-object.xml'),
];

function printResult(result: ValidationResult): void {
  console.log(`--- Validating: ${result.filePath} ---`);
  console.log(`Status: ${result.isValid ? 'PASS' : 'FAIL'}`);
  console.log(`Errors: ${result.errors.length}`);
  for (const err of result.errors) {
    const prefix = err.line !== null ? `Line ${err.line}: ` : '';
    console.log(`  ${prefix}${err.message}`);
  }
  console.log('');
}

function main(): void {
  let anyFailed = false;

  for (const xmlPath of XML_FILES) {
    const result = validateXml(xmlPath, XSD_PATH);
    printResult(result);
    if (!result.isValid) {
      anyFailed = true;
    }
  }

  if (anyFailed) {
    process.exitCode = 1;
  }
}

main();
