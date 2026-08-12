import { readFile } from 'fs/promises';
import { XMLParser, XMLValidator } from 'fast-xml-parser';
import { FileNotFoundError, XmlParseError } from './errors';

export async function loadAndParseXml(filePath: string): Promise<Record<string, unknown>> {
  let content: string;
  try {
    content = await readFile(filePath, 'utf-8');
  } catch (err: unknown) {
    throw new FileNotFoundError(filePath, err);
  }

  if (!content.trim()) {
    throw new XmlParseError(filePath, new Error('File is empty'));
  }

  const validation = XMLValidator.validate(content, { allowBooleanAttributes: true });
  if (validation !== true) {
    const { msg, line, col } = validation.err;
    throw new XmlParseError(filePath, new Error(`${msg} (line ${line}, col ${col})`));
  }

  const parser = new XMLParser({ ignoreAttributes: false });
  return parser.parse(content) as Record<string, unknown>;
}
