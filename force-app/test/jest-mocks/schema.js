// Jest mock for @salesforce/schema/* imports
// Returns the schema key as an object with objectApiName or fieldApiName
const handler = {
    get(target, key) {
        // Handle field references like Object__c.Field__c
        if (key.includes('.')) {
            const [objectApiName, fieldApiName] = key.split('.');
            return { objectApiName, fieldApiName };
        }
        return { objectApiName: key };
    }
};

module.exports = new Proxy({}, handler);
