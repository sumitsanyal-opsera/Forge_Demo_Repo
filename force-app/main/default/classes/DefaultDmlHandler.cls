public without sharing class DefaultDmlHandler implements IDmlHandler {
    public void insertRecord(SObject record) {
        Database.insert(record, true);
    }

    public void insertRecords(List<SObject> records) {
        Database.insert(records, true);
    }
}
