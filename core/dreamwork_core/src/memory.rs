use std::collections::HashMap;

use crate::ingestion::ManualEntry;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RepositoryError {
    NotFound,
}

pub trait EntryRepository {
    fn save_manual_entry(&mut self, entry: ManualEntry) -> Result<(), RepositoryError>;
    fn get_manual_entry(&self, id: &str) -> Result<ManualEntry, RepositoryError>;
}

#[derive(Debug, Default)]
pub struct InMemoryRepository {
    manual_entries: HashMap<String, ManualEntry>,
}

impl EntryRepository for InMemoryRepository {
    fn save_manual_entry(&mut self, entry: ManualEntry) -> Result<(), RepositoryError> {
        self.manual_entries.insert(entry.id.clone(), entry);
        Ok(())
    }

    fn get_manual_entry(&self, id: &str) -> Result<ManualEntry, RepositoryError> {
        self.manual_entries
            .get(id)
            .cloned()
            .ok_or(RepositoryError::NotFound)
    }
}

impl InMemoryRepository {
    pub fn manual_entry_count(&self) -> usize {
        self.manual_entries.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ingestion::{ManualEntry, ManualField};

    #[test]
    fn manual_entry_persists_to_repository() {
        let mut repo = InMemoryRepository::default();
        let entry = ManualEntry {
            id: "entry-1".to_string(),
            fields: vec![ManualField {
                key: "first_name".to_string(),
                value: "Dana".to_string(),
            }],
        };

        repo.save_manual_entry(entry.clone()).unwrap();
        let persisted = repo.get_manual_entry("entry-1").unwrap();

        assert_eq!(persisted, entry);
    }
}
