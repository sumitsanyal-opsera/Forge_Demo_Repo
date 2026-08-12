// Jest mock for @salesforce/label/* imports
// Returns the label key as a string — replace with actual values for snapshot tests
const handler = {
    get(target, key) {
        return key;
    }
};

module.exports = new Proxy({}, handler);
