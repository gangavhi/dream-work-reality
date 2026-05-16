use std::collections::HashMap;

use super::{EntryRepository, ExtractionRepository, RepositoryError};
use crate::extraction::ExtractionRunRecord;
use crate::ingestion::ManualEntry;

#[derive(Debug, Default)]
pub struct InMemoryRepository {
    manual_entries: HashMap<String, ManualEntry>,
    extraction_runs: Vec<ExtractionRunRecord>,
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

    fn delete_manual_entry(&mut self, id: &str) -> Result<(), RepositoryError> {
        let removed = self.manual_entries.remove(id);
        if removed.is_some() {
            Ok(())
        } else {
            Err(RepositoryError::NotFound)
        }
    }

    fn manual_entry_count(&self) -> usize {
        self.manual_entries.len()
    }

    fn list_manual_entries(&self) -> Result<Vec<ManualEntry>, RepositoryError> {
        let mut v: Vec<ManualEntry> = self.manual_entries.values().cloned().collect();
        v.sort_by(|a, b| a.id.cmp(&b.id));
        Ok(v)
    }
}

impl ExtractionRepository for InMemoryRepository {
    fn save_extraction_run(&mut self, record: &ExtractionRunRecord) -> Result<(), RepositoryError> {
        self.extraction_runs.push(record.clone());
        Ok(())
    }

    fn extraction_run_count(&self) -> usize {
        self.extraction_runs.len()
    }

    fn get_extraction_run_document_json(&self, id: &str) -> Result<String, RepositoryError> {
        let found = self
            .extraction_runs
            .iter()
            .find(|r| r.id == id)
            .ok_or(RepositoryError::NotFound)?;
        serde_json::to_string(&found.document)
            .map_err(|e| RepositoryError::Persistence(e.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ingestion::ManualField;

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
