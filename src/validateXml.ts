import * as libxmljs from 'libxmljs2';

export interface ValidationResult {
  line: number;
  column: number;
  message: string;
  phase: 'wellformedness' | 'xsd';
  xsdRule: string | null;
}

export const SAFE_PARSE_OPTIONS = {
  noent: false,
  nonet: true,
  dtdload: false,
  dtdattr: false,
} as const;

export function validateXml(xmlContent: string): ValidationResult[] {
  if (!xmlContent) {
    return [
      {
        line: 0,
        column: 0,
        message: 'Input is empty',
        phase: 'wellformedness',
        xsdRule: null,
      },
    ];
  }

  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    libxmljs.parseXml(xmlContent, SAFE_PARSE_OPTIONS as any);
    return [];
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    const lineMatch = msg.match(/line[:\s]+(\d+)/i);
    const colMatch = msg.match(/col(?:umn)?[:\s]+(\d+)/i);
    const line = lineMatch ? parseInt(lineMatch[1], 10) : 0;
    const column = colMatch ? parseInt(colMatch[1], 10) : 0;
    return [
      {
        line,
        column,
        message: msg.trim(),
        phase: 'wellformedness',
        xsdRule: null,
      },
    ];
  }
}

export function validateXmlAgainstXsd(xmlContent: string, xsdContent: string): ValidationResult[] {
  const wellformedErrors = validateXml(xmlContent);
  if (wellformedErrors.length > 0) {
    return wellformedErrors;
  }

  let xsdDoc: libxmljs.Document;
  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    xsdDoc = libxmljs.parseXml(xsdContent, SAFE_PARSE_OPTIONS as any);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return [
      {
        line: 0,
        column: 0,
        message: `Schema could not be parsed: ${msg.trim()}`,
        phase: 'xsd',
        xsdRule: null,
      },
    ];
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const xmlDoc = libxmljs.parseXml(xmlContent, SAFE_PARSE_OPTIONS as any);
  xmlDoc.validate(xsdDoc);

  return xmlDoc.validationErrors.map((e) => {
    const ruleMatch = e.message.match(/\bcvc-[\w.-]+/);
    return {
      line: e.line,
      column: e.column,
      message: e.message.trim(),
      phase: 'xsd' as const,
      xsdRule: ruleMatch ? ruleMatch[0] : null,
    };
  });
}
