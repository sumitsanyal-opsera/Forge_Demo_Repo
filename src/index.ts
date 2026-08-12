import * as fs from 'fs';
import { parseXml } from './validate/parseXml';
import { validateAgainstXsd } from './validate/validateAgainstXsd';
import { formatResults } from './validate/formatResults';

function main(): void {
  const xmlPath = process.argv[2];
  const xsdPath = process.argv[3];

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

  const output = formatResults(xmlPath, result);
  console.log(output);

  process.exit(result.valid ? 0 : 1);
}

main();
