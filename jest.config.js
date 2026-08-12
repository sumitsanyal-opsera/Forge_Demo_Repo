const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    // Project-specific module name mappings for custom labels, schema, and static resources
    moduleNameMapper: {
        '^@salesforce/label/(.+)$': '<rootDir>/force-app/test/jest-mocks/labels.js',
        '^@salesforce/schema/(.+)$': '<rootDir>/force-app/test/jest-mocks/schema.js',
        '^@salesforce/resourceUrl/(.+)$': '<rootDir>/force-app/test/jest-mocks/staticResource.js',
        '^@salesforce/apex$': '<rootDir>/force-app/test/jest-mocks/apex.js',
        '^@salesforce/apex/(.+)$': '<rootDir>/force-app/test/jest-mocks/apex.js',
        '^lightning/navigation$': '<rootDir>/force-app/test/jest-mocks/lightningNavigation.js',
        '^lightning/platformShowToastEvent$':
            '<rootDir>/force-app/test/jest-mocks/lightningPlatformShowToastEvent.js',
        '^lightning/uiRecordApi$': '<rootDir>/force-app/test/jest-mocks/lightningUiRecordApi.js',
        '^c/(.+)$': '<rootDir>/force-app/main/default/lwc/$1/$1',
        ...jestConfig.moduleNameMapper
    },
    // Collect coverage from LWC source files
    collectCoverageFrom: ['force-app/main/default/lwc/**/*.js'],
    // Test files location
    testMatch: ['**/__tests__/**/*.test.js'],
    // Setup files
    setupFiles: [],
    // Transform configuration (inherited from sfdx-lwc-jest)
    testEnvironment: 'jsdom',
    // Coverage thresholds
    coverageThreshold: {
        global: {
            branches: 60,
            functions: 60,
            lines: 60,
            statements: 60
        }
    }
};
