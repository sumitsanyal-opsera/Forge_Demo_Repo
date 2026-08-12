export class FileNotFoundError extends Error {
  constructor(filePath: string, cause?: unknown) {
    const detail = cause instanceof Error ? cause.message : String(cause ?? '');
    super(`File not found: ${filePath}${detail ? ` — ${detail}` : ''}`);
    this.name = 'FileNotFoundError';
  }
}

export class XmlParseError extends Error {
  constructor(filePath: string, cause?: unknown) {
    const detail = cause instanceof Error ? cause.message : String(cause ?? '');
    super(`XML parse error in ${filePath}${detail ? `: ${detail}` : ''}`);
    this.name = 'XmlParseError';
  }
}

export class SchemaError extends Error {
  constructor(schemaPath: string, cause?: unknown) {
    const detail = cause instanceof Error ? cause.message : String(cause ?? '');
    super(`Schema error in ${schemaPath}${detail ? `: ${detail}` : ''}`);
    this.name = 'SchemaError';
  }
}
