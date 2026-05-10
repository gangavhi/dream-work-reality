//! Crate-integration tests (filesystem SQLite + migrations).

use dreamwork_core::{
    ingestion::{ManualEntry, ManualField},
    memory::{migrate_sqlite_schema, EntryRepository, RepositoryBackend},
};
use rusqlite::Connection;
use std::path::Path;

#[test]
fn file_sqlite_survives_repository_reopen() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("vault.sqlite");

    {
        let mut backend = RepositoryBackend::open_sqlite_file(Path::new(&db_path)).unwrap();
        backend
            .save_manual_entry(ManualEntry {
                id: "persist-1".to_string(),
                fields: vec![ManualField {
                    key: "display_name".to_string(),
                    value: "Casey".to_string(),
                }],
            })
            .unwrap();
    }

    let backend = RepositoryBackend::open_sqlite_file(Path::new(&db_path)).unwrap();
    assert_eq!(backend.manual_entry_count(), 1);
    let loaded = backend.get_manual_entry("persist-1").unwrap();
    assert_eq!(loaded.fields.len(), 1);
}

#[test]
fn migrate_sqlite_schema_is_idempotent() {
    let mut conn = Connection::open_in_memory().unwrap();
    migrate_sqlite_schema(&mut conn).unwrap();
    migrate_sqlite_schema(&mut conn).unwrap();
}
