import * as libxmljs from 'libxmljs2';

// Verify libxmljs2 loaded successfully by accessing the module
const version: string = libxmljs.version;

console.log('Salesforce Metadata XML Validator Prototype ready');
console.log(`libxmljs2 loaded (libxml2 version: ${version})`);
