import { describe, it, expect } from 'vitest';
import { parseXml } from '../../src/validate/parseXml';

const VALID_XML = `<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>MyObject__c</fullName>
  <label>My Object</label>
</CustomObject>`;

const MALFORMED_XML = `<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>MyObject__c</fullName>
  <label>unclosed tag`;

describe('parseXml', () => {
  it('returns valid:true and empty errors for well-formed XML', () => {
    const result = parseXml(VALID_XML);
    expect(result.valid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  it('returns valid:false with errors for malformed XML with unclosed tag', () => {
    const result = parseXml(MALFORMED_XML);
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0].message).toBeTruthy();
    expect(typeof result.errors[0].line).toBe('number');
    expect(typeof result.errors[0].column).toBe('number');
  });

  it('returns valid:false for an empty string without throwing', () => {
    const result = parseXml('');
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0].message).toBeTruthy();
  });
});
