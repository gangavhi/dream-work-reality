#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChangeSource {
    ManualEntry,
    DocumentOcr,
    FormAutofill,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HistoryRecord {
    pub field_key: String,
    pub value: String,
    pub source: ChangeSource,
    pub timestamp_ms: u64,
}

pub trait HistoryStore {
    fn append(&mut self, record: HistoryRecord);
    fn list_for_field(&self, field_key: &str) -> Vec<HistoryRecord>;
}

#[derive(Debug, Default)]
pub struct InMemoryHistoryStore {
    records: Vec<HistoryRecord>,
}

impl HistoryStore for InMemoryHistoryStore {
    fn append(&mut self, record: HistoryRecord) {
        self.records.push(record);
    }

    fn list_for_field(&self, field_key: &str) -> Vec<HistoryRecord> {
        self.records
            .iter()
            .filter(|record| record.field_key == field_key)
            .cloned()
            .collect()
    }
}
