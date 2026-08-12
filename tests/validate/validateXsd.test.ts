import { describe, it, expect } from 'vitest';
import * as path from 'path';
import { validateAgainstXsd } from '../../src/validate/validateXsd';

const FIXTURES = path.resolve(__dirname, '../fixtures');
const CUSTOM_OBJECT_XSD = path.join(FIXTURES, 'CustomObject.xsd');

const VALID_XML = `<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>MyObject__c</fullName>
  <label>My Object</label>
  <deploymentStatus>Deployed</deploymentStatus>
</CustomObject>`;

const INVALID_XML = `<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
  <bogusElement>should not be here</bogusElement>
</CustomObject>`;

describe('validateAgainstXsd', () => {
  it('returns valid:true and empty errors for XSD-conformant XML', () => {
    const result = validateAgainstXsd(VALID_XML, CUSTOM_OBJECT_XSD);
    expect(result.valid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  it('returns valid:false with errors for XML that violates the XSD', () => {
    const result = validateAgainstXsd(INVALID_XML, CUSTOM_OBJECT_XSD);
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0].message).toBeTruthy();
  });

  it('returns valid:false with a descriptive error for a non-existent XSD path', () => {
    const result = validateAgainstXsd(VALID_XML, '/nonexistent/path/schema.xsd');
    expect(result.valid).toBe(false);
    expect(result.errors).toHaveLength(1);
    expect(result.errors[0].message).toContain('Cannot read XSD file');
  });
});
