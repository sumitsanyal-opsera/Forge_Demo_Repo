import * as assert from 'assert';
import * as path from 'path';
import { validateXml } from '../src/validate';

const FIXTURES_DIR = path.resolve(__dirname, '..', 'fixtures');
const XSD_PATH = path.join(FIXTURES_DIR, 'custom-object.xsd');
const VALID_XML = path.join(FIXTURES_DIR, 'valid-custom-object.xml');
const INVALID_XML = path.join(FIXTURES_DIR, 'invalid-custom-object.xml');

// Test 1: valid XML returns isValid true with empty errors array
const validResult = validateXml(VALID_XML, XSD_PATH);
assert.ok(
  validResult.isValid,
  `Expected valid XML to pass, got errors: ${JSON.stringify(validResult.errors)}`
);
assert.strictEqual(validResult.errors.length, 0, 'Expected no errors for valid XML');
console.log('✓ Valid XML passes validation');

// Test 2: invalid XML returns isValid false with errors populated
const invalidResult = validateXml(INVALID_XML, XSD_PATH);
assert.ok(!invalidResult.isValid, 'Expected invalid XML to fail validation');
assert.ok(
  invalidResult.errors.length >= 2,
  `Expected at least 2 errors, got ${invalidResult.errors.length}: ${JSON.stringify(invalidResult.errors)}`
);
console.log(`✓ Invalid XML fails validation with ${invalidResult.errors.length} error(s)`);

// Test 3: error objects contain message and line number
const errorsWithLine = invalidResult.errors.filter((e) => e.line !== null);
assert.ok(
  errorsWithLine.length > 0,
  'Expected at least one error with a line number'
);
console.log('✓ Errors include line number information');

console.log('\nAll tests passed.');
