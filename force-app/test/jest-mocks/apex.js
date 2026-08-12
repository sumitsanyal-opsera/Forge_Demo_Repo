// Jest mock for @salesforce/apex and @salesforce/apex/* imports
// All Apex wire adapters and imperative calls are mocked as jest.fn()
// Tests use jest.mock('@salesforce/apex/<ClassName>.<methodName>') to override behaviour

const mockApex = jest.fn();
mockApex.mockResolvedValue(undefined);

module.exports = mockApex;
