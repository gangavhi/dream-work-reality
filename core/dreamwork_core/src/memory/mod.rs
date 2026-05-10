//! Persistent and in-memory [`EntryRepository`] implementations.
//!
//! SQLite uses bundled [`rusqlite`] by default. Enable feature **`sqlcipher`** and link a SQLCipher-enabled `libsqlite3`
//! (see repository `docs/core-development.md`) so `PRAGMA key` activates encryption.

mod in_memory;
mod sqlite;

pub use in_memory::InMemoryRepository;
pub use sqlite::{migrate_sqlite_schema, SqliteEntryRepository};

use crate::extraction::ExtractionRunRecord;
use crate::ingestion::ManualEntry;

/// Storage backend errors surfaced to callers (no panics across FFI/API boundaries).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RepositoryError {
    NotFound,
    Persistence(String),
}

impl std::fmt::Display for RepositoryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RepositoryError::NotFound => write!(f, "entry not found"),
            RepositoryError::Persistence(msg) => write!(f, "{msg}"),
        }
    }
}

impl std::error::Error for RepositoryError {}

pub trait EntryRepository {
    fn save_manual_entry(&mut self, entry: ManualEntry) -> Result<(), RepositoryError>;
    fn get_manual_entry(&self, id: &str) -> Result<ManualEntry, RepositoryError>;
    fn manual_entry_count(&self) -> usize;
    fn list_manual_entries(&self) -> Result<Vec<ManualEntry>, RepositoryError>;
}

pub trait ExtractionRepository {
    fn save_extraction_run(&mut self, record: &ExtractionRunRecord) -> Result<(), RepositoryError>;
    fn extraction_run_count(&self) -> usize;
    fn get_extraction_run_document_json(&self, id: &str) -> Result<String, RepositoryError>;
}

/// Runtime-selectable backend for FFI and HTTP surfaces (ADR 0003 shared core).
#[derive(Debug)]
pub enum RepositoryBackend {
    Memory(InMemoryRepository),
    Sqlite(SqliteEntryRepository),
}

impl RepositoryBackend {
    pub fn new_in_memory_sqlite() -> Result<Self, rusqlite::Error> {
        Ok(Self::Sqlite(SqliteEntryRepository::open_in_memory()?))
    }

    pub fn open_sqlite_file(path: &std::path::Path) -> Result<Self, rusqlite::Error> {
        Ok(Self::Sqlite(SqliteEntryRepository::open(path)?))
    }

    pub fn open_sqlite_file_encrypted(
        path: &std::path::Path,
        encryption_key_pragma: Option<&str>,
    ) -> Result<Self, rusqlite::Error> {
        Ok(Self::Sqlite(SqliteEntryRepository::open_encrypted(
            path,
            encryption_key_pragma,
        )?))
    }

    pub fn memory_only() -> Self {
        Self::Memory(InMemoryRepository::default())
    }
}

impl ExtractionRepository for RepositoryBackend {
    fn save_extraction_run(&mut self, record: &ExtractionRunRecord) -> Result<(), RepositoryError> {
        match self {
            RepositoryBackend::Memory(r) => r.save_extraction_run(record),
            RepositoryBackend::Sqlite(r) => r.save_extraction_run(record),
        }
    }

    fn extraction_run_count(&self) -> usize {
        match self {
            RepositoryBackend::Memory(r) => r.extraction_run_count(),
            RepositoryBackend::Sqlite(r) => r.extraction_run_count(),
        }
    }

    fn get_extraction_run_document_json(&self, id: &str) -> Result<String, RepositoryError> {
        match self {
            RepositoryBackend::Memory(r) => r.get_extraction_run_document_json(id),
            RepositoryBackend::Sqlite(r) => r.get_extraction_run_document_json(id),
        }
    }
}

impl EntryRepository for RepositoryBackend {
    fn save_manual_entry(&mut self, entry: ManualEntry) -> Result<(), RepositoryError> {
        match self {
            RepositoryBackend::Memory(r) => r.save_manual_entry(entry),
            RepositoryBackend::Sqlite(r) => r.save_manual_entry(entry),
        }
    }

    fn get_manual_entry(&self, id: &str) -> Result<ManualEntry, RepositoryError> {
        match self {
            RepositoryBackend::Memory(r) => r.get_manual_entry(id),
            RepositoryBackend::Sqlite(r) => r.get_manual_entry(id),
        }
    }

    fn manual_entry_count(&self) -> usize {
        match self {
            RepositoryBackend::Memory(r) => r.manual_entry_count(),
            RepositoryBackend::Sqlite(r) => r.manual_entry_count(),
        }
    }

    fn list_manual_entries(&self) -> Result<Vec<ManualEntry>, RepositoryError> {
        match self {
            RepositoryBackend::Memory(r) => r.list_manual_entries(),
            RepositoryBackend::Sqlite(r) => r.list_manual_entries(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::extraction::{default_import_meta, ExtractionRunRecord};
    use crate::ingestion::ManualField;
    use crate::ocr::{NormRect, NormalizedDocument, Page, TextBlock};

    #[test]
    fn repository_backend_round_trips_through_sqlite() {
        let mut backend =
            RepositoryBackend::new_in_memory_sqlite().expect("sqlite in-memory opens");
        let entry = ManualEntry {
            id: "p-1".to_string(),
            fields: vec![ManualField {
                key: "display_name".to_string(),
                value: "Sam".to_string(),
            }],
        };
        backend.save_manual_entry(entry.clone()).unwrap();
        assert_eq!(backend.manual_entry_count(), 1);
        assert_eq!(backend.get_manual_entry("p-1").unwrap(), entry);
    }

    #[test]
    fn repository_backend_persists_extraction_run_sqlite() {
        let mut backend =
            RepositoryBackend::new_in_memory_sqlite().expect("sqlite in-memory opens");
        let doc = NormalizedDocument {
            pages: vec![Page {
                blocks: vec![TextBlock {
                    text: "x".into(),
                    confidence: 1.0,
                    bounds: NormRect {
                        x: 0.0,
                        y: 0.0,
                        width: 1.0,
                        height: 0.1,
                    },
                }],
            }],
        };
        let meta = default_import_meta();
        let record = ExtractionRunRecord::new(doc.clone(), meta);
        backend.save_extraction_run(&record).unwrap();
        assert_eq!(backend.extraction_run_count(), 1);
        let json = backend
            .get_extraction_run_document_json(&record.id)
            .unwrap();
        let parsed: NormalizedDocument = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, doc);
    }
}
