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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn history_store_filters_by_field_key() {
        let mut store = InMemoryHistoryStore::default();
        store.append(HistoryRecord {
            field_key: "phone".to_string(),
            value: "111".to_string(),
            source: ChangeSource::ManualEntry,
            timestamp_ms: 1,
        });
        store.append(HistoryRecord {
            field_key: "email".to_string(),
            value: "a@b".to_string(),
            source: ChangeSource::FormAutofill,
            timestamp_ms: 2,
        });

        let phones = store.list_for_field("phone");
        assert_eq!(phones.len(), 1);
        assert_eq!(phones[0].value, "111");
    }
}
