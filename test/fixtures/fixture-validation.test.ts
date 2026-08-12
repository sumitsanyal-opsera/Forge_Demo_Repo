import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import * as libxmljs from 'libxmljs2';

const FIXTURES_DIR = path.resolve(__dirname, '.');
const SCHEMAS_DIR = path.join(FIXTURES_DIR, 'schemas');
const VALID_DIR = path.join(FIXTURES_DIR, 'valid', 'objects');
const INVALID_DIR = path.join(FIXTURES_DIR, 'invalid');

describe('fixture smoke tests', () => {
  let xsdDoc: libxmljs.Document;
  let expectedJson: { expectedErrorCount: number; expectedErrorLineNumber: number; expectedErrorMessageSubstring: string };

  it('XSD schema file exists and parses without error', () => {
    const xsdContent = fs.readFileSync(path.join(SCHEMAS_DIR, 'metadata-61.0.xsd'), 'utf-8');
    xsdDoc = libxmljs.parseXml(xsdContent);
    expect(xsdDoc).toBeDefined();
    expect(typeof xsdDoc.validate).toBe('function');
  });

  it('valid fixture passes XSD validation with zero errors', () => {
    const xsdContent = fs.readFileSync(path.join(SCHEMAS_DIR, 'metadata-61.0.xsd'), 'utf-8');
    xsdDoc = libxmljs.parseXml(xsdContent);
    const xmlContent = fs.readFileSync(
      path.join(VALID_DIR, 'Account.object-meta.xml'),
      'utf-8'
    );
    const xmlDoc = libxmljs.parseXml(xmlContent);
    const isValid = xmlDoc.validate(xsdDoc);
    expect(isValid).toBe(true);
    expect(xmlDoc.validationErrors).toHaveLength(0);
  });

  it('invalid fixture fails XSD validation with at least one error', () => {
    const xsdContent = fs.readFileSync(path.join(SCHEMAS_DIR, 'metadata-61.0.xsd'), 'utf-8');
    xsdDoc = libxmljs.parseXml(xsdContent);
    const xmlContent = fs.readFileSync(
      path.join(INVALID_DIR, 'InvalidObject.object-meta.xml'),
      'utf-8'
    );
    expectedJson = JSON.parse(
      fs.readFileSync(path.join(INVALID_DIR, 'InvalidObject.expected.json'), 'utf-8')
    );
    const xmlDoc = libxmljs.parseXml(xmlContent);
    xmlDoc.validate(xsdDoc);
    expect(xmlDoc.validationErrors.length).toBeGreaterThanOrEqual(expectedJson.expectedErrorCount);
    const firstError = xmlDoc.validationErrors[0];
    expect(firstError.message).toContain(expectedJson.expectedErrorMessageSubstring);
  });
});
