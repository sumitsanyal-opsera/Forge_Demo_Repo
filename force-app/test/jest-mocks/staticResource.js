// Jest mock for @salesforce/resourceUrl/* imports
const handler = {
    get(target, key) {
        return `/resource/${key}`;
    }
};

module.exports = new Proxy({}, handler);
