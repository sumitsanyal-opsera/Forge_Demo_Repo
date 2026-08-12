# sf-metadata-validator-prototype

A minimal TypeScript prototype for Salesforce Metadata XML validation. Validates Salesforce metadata XML files against official Salesforce XSD schemas using `libxmljs2` (libxml2 bindings).

## Prerequisites

Node.js 18+ is required. `libxmljs2` requires native build tools:

```
# Ubuntu / Debian
sudo apt-get install python3 make g++ libxml2-dev

# macOS (via Homebrew)
brew install libxml2
```

If `npm install` fails with a native binding compilation error, ensure the above tools are installed and retry.

## Getting Started

```bash
npm install
npm start
```

`npm start` runs `npx ts-node src/main.ts` and should print:

```
Salesforce Metadata XML Validator Prototype ready
```

## Project Structure

```
src/
  main.ts       # Entry point — imports libxmljs2, prints startup message
tsconfig.json   # TypeScript compiler config (ES2022, CommonJS, strict)
package.json    # Project manifest and scripts
```

## Dependencies

| Package       | Purpose                                      |
|---------------|----------------------------------------------|
| `typescript`  | TypeScript compiler                          |
| `ts-node`     | Run TypeScript directly without pre-compiling |
| `libxmljs2`   | libxml2 bindings for XML/XSD parsing          |
