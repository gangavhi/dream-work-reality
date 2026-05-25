//! Canonical SQLite persistence for manual entries (ADR 0002). Optional **SQLCipher** via `PRAGMA key` when feature **`sqlcipher`** is enabled and the binary links SQLCipher.

use rusqlite::{params, Connection};

use super::{EntryRepository, ExtractionRepository, RepositoryError};
use crate::db::{apply_core_migrations, MigrationError};
use crate::extraction::ExtractionRunRecord;
use crate::ingestion::{ManualEntry, ManualField};

/// Opens or upgrades schema via [`apply_core_migrations`].
pub fn migrate_sqlite_schema(conn: &mut Connection) -> rusqlite::Result<()> {
    apply_core_migrations(conn).map_err(|e| match e {
        MigrationError::Sqlite(se) => se,
        other => rusqlite::Error::ToSqlConversionFailure(Box::new(other)),
    })
}

#[cfg(feature = "sqlcipher")]
fn apply_encryption_pragma(
    conn: &Connection,
    encryption_key_pragma: Option<&str>,
) -> rusqlite::Result<()> {
    if let Some(k) = encryption_key_pragma {
        conn.pragma_update(None, "key", k)?;
    }
    Ok(())
}

#[cfg(not(feature = "sqlcipher"))]
fn apply_encryption_pragma(
    _conn: &Connection,
    _encryption_key_pragma: Option<&str>,
) -> rusqlite::Result<()> {
    Ok(())
}

#[derive(Debug)]
pub struct SqliteEntryRepository {
    conn: Connection,
}

impl SqliteEntryRepository {
    /// Borrow the underlying connection for schema introspection and ML storage apply.
    pub fn connection_mut(&mut self) -> &mut Connection {
        &mut self.conn
    }

    pub fn open_in_memory() -> rusqlite::Result<Self> {
        Self::open_in_memory_encrypted(None)
    }

    /// When **`sqlcipher`** feature is enabled, supply `Some("x'…'"| passphrase)` per SQLCipher docs **before** DDL runs.
    pub fn open_in_memory_encrypted(encryption_key_pragma: Option<&str>) -> rusqlite::Result<Self> {
        let mut conn = Connection::open_in_memory()?;
        apply_encryption_pragma(&conn, encryption_key_pragma)?;
        apply_core_migrations(&mut conn).map_err(|e| match e {
            MigrationError::Sqlite(se) => se,
            other => rusqlite::Error::ToSqlConversionFailure(Box::new(other)),
        })?;
        Ok(Self { conn })
    }

    pub fn open(path: &std::path::Path) -> rusqlite::Result<Self> {
        Self::open_encrypted(path, None)
    }

    pub fn open_encrypted(
        path: &std::path::Path,
        encryption_key_pragma: Option<&str>,
    ) -> rusqlite::Result<Self> {
        let mut conn = Connection::open(path)?;
        apply_encryption_pragma(&conn, encryption_key_pragma)?;
        apply_core_migrations(&mut conn).map_err(|e| match e {
            MigrationError::Sqlite(se) => se,
            other => rusqlite::Error::ToSqlConversionFailure(Box::new(other)),
        })?;
        Ok(Self { conn })
    }
}

fn map_sqlite(err: rusqlite::Error) -> RepositoryError {
    RepositoryError::Persistence(err.to_string())
}

impl EntryRepository for SqliteEntryRepository {
    fn save_manual_entry(&mut self, entry: ManualEntry) -> Result<(), RepositoryError> {
        let tx = self.conn.transaction().map_err(map_sqlite)?;
        tx.execute(
            "DELETE FROM manual_field WHERE entry_id = ?",
            params![&entry.id],
        )
        .map_err(map_sqlite)?;
        tx.execute(
            "INSERT OR IGNORE INTO manual_entry (id) VALUES (?)",
            params![&entry.id],
        )
        .map_err(map_sqlite)?;
        for field in &entry.fields {
            tx.execute(
                "INSERT INTO manual_field (entry_id, field_key, value) VALUES (?, ?, ?)",
                params![&entry.id, &field.key, &field.value],
            )
            .map_err(map_sqlite)?;
        }
        tx.commit().map_err(map_sqlite)?;
        Ok(())
    }

    fn get_manual_entry(&self, id: &str) -> Result<ManualEntry, RepositoryError> {
        let exists: i64 = self
            .conn
            .query_row(
                "SELECT COUNT(*) FROM manual_entry WHERE id = ?",
                params![id],
                |row| row.get(0),
            )
            .map_err(map_sqlite)?;
        if exists == 0 {
            return Err(RepositoryError::NotFound);
        }

        let mut stmt = self
            .conn
            .prepare(
                "SELECT field_key, value FROM manual_field WHERE entry_id = ? ORDER BY field_key ASC",
            )
            .map_err(map_sqlite)?;

        let rows = stmt
            .query_map(params![id], |row| {
                Ok(ManualField {
                    key: row.get(0)?,
                    value: row.get(1)?,
                })
            })
            .map_err(map_sqlite)?;

        let mut fields = Vec::new();
        for row in rows {
            fields.push(row.map_err(map_sqlite)?);
        }

        Ok(ManualEntry {
            id: id.to_string(),
            fields,
        })
    }

    fn delete_manual_entry(&mut self, id: &str) -> Result<(), RepositoryError> {
        let tx = self.conn.transaction().map_err(map_sqlite)?;
        tx.execute("DELETE FROM manual_field WHERE entry_id = ?", params![id])
            .map_err(map_sqlite)?;
        let deleted = tx
            .execute("DELETE FROM manual_entry WHERE id = ?", params![id])
            .map_err(map_sqlite)?;
        tx.commit().map_err(map_sqlite)?;
        if deleted == 0 {
            Err(RepositoryError::NotFound)
        } else {
            Ok(())
        }
    }

    fn manual_entry_count(&self) -> usize {
        self.conn
            .query_row("SELECT COUNT(*) FROM manual_entry", [], |row| {
                row.get::<_, i64>(0)
            })
            .map(|n| n as usize)
            .unwrap_or(0)
    }

    fn list_manual_entries(&self) -> Result<Vec<ManualEntry>, RepositoryError> {
        let mut stmt = self
            .conn
            .prepare("SELECT id FROM manual_entry ORDER BY id ASC")
            .map_err(map_sqlite)?;
        let ids: Vec<String> = stmt
            .query_map([], |row| row.get::<_, String>(0))
            .map_err(map_sqlite)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(map_sqlite)?;
        let mut out = Vec::with_capacity(ids.len());
        for id in ids {
            out.push(self.get_manual_entry(&id)?);
        }
        Ok(out)
    }
}

impl ExtractionRepository for SqliteEntryRepository {
    fn save_extraction_run(&mut self, record: &ExtractionRunRecord) -> Result<(), RepositoryError> {
        let document_json = serde_json::to_string(&record.document)
            .map_err(|e| RepositoryError::Persistence(e.to_string()))?;
        self.conn
            .execute(
                "INSERT OR REPLACE INTO extraction_run (id, created_at_ms, engine_id, model_revision, language_tag, document_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![
                    &record.id,
                    record.created_at_ms,
                    &record.meta.engine_id.0,
                    &record.meta.model_revision,
                    &record.meta.language_tag,
                    document_json,
                ],
            )
            .map_err(map_sqlite)?;
        Ok(())
    }

    fn extraction_run_count(&self) -> usize {
        self.conn
            .query_row("SELECT COUNT(*) FROM extraction_run", [], |row| {
                row.get::<_, i64>(0)
            })
            .map(|n| n as usize)
            .unwrap_or(0)
    }

    fn get_extraction_run_document_json(&self, id: &str) -> Result<String, RepositoryError> {
        let json: String = self
            .conn
            .query_row(
                "SELECT document_json FROM extraction_run WHERE id = ?",
                params![id],
                |row| row.get(0),
            )
            .map_err(|e| match e {
                rusqlite::Error::QueryReturnedNoRows => RepositoryError::NotFound,
                other => map_sqlite(other),
            })?;
        Ok(json)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::apply_adhoc_ddl;
    use crate::ingestion::ManualField;

    #[test]
    fn list_manual_entries_returns_sorted_ids() {
        let mut repo = SqliteEntryRepository::open_in_memory().unwrap();
        repo.save_manual_entry(ManualEntry {
            id: "z-last".into(),
            fields: vec![ManualField {
                key: "display_name".into(),
                value: "Zed".into(),
            }],
        })
        .unwrap();
        repo.save_manual_entry(ManualEntry {
            id: "a-first".into(),
            fields: vec![ManualField {
                key: "display_name".into(),
                value: "Ann".into(),
            }],
        })
        .unwrap();
        let list = repo.list_manual_entries().unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].id, "a-first");
        assert_eq!(list[1].id, "z-last");
    }

    #[test]
    fn sqlite_replace_updates_fields_atomically() {
        let mut repo = SqliteEntryRepository::open_in_memory().unwrap();
        let first = ManualEntry {
            id: "a".to_string(),
            fields: vec![ManualField {
                key: "display_name".to_string(),
                value: "First".to_string(),
            }],
        };
        repo.save_manual_entry(first).unwrap();
        let second = ManualEntry {
            id: "a".to_string(),
            fields: vec![ManualField {
                key: "display_name".to_string(),
                value: "Second".to_string(),
            }],
        };
        repo.save_manual_entry(second.clone()).unwrap();
        assert_eq!(repo.manual_entry_count(), 1);
        assert_eq!(repo.get_manual_entry("a").unwrap(), second);
    }

    #[test]
    fn migrate_is_idempotent() {
        let mut conn = Connection::open_in_memory().unwrap();
        migrate_sqlite_schema(&mut conn).unwrap();
        migrate_sqlite_schema(&mut conn).unwrap();
        let repo = SqliteEntryRepository::open_in_memory().unwrap();
        assert_eq!(repo.manual_entry_count(), 0);
    }

    #[test]
    fn extraction_run_round_trips_through_sqlite() {
        let mut repo = SqliteEntryRepository::open_in_memory().unwrap();
        let doc = crate::ocr::NormalizedDocument {
            pages: vec![crate::ocr::Page {
                blocks: vec![crate::ocr::TextBlock {
                    text: "ocr-text".into(),
                    confidence: 0.9,
                    bounds: crate::ocr::NormRect {
                        x: 0.0,
                        y: 0.0,
                        width: 0.5,
                        height: 0.05,
                    },
                }],
            }],
        };
        let record = crate::extraction::ExtractionRunRecord::new(
            doc.clone(),
            crate::extraction::default_import_meta(),
        );
        repo.save_extraction_run(&record).unwrap();
        assert_eq!(repo.extraction_run_count(), 1);
        let json = repo.get_extraction_run_document_json(&record.id).unwrap();
        let round: crate::ocr::NormalizedDocument = serde_json::from_str(&json).unwrap();
        assert_eq!(round, doc);
    }

    #[test]
    fn adhoc_ddl_visible_after_migration() {
        let mut conn = Connection::open_in_memory().unwrap();
        migrate_sqlite_schema(&mut conn).unwrap();
        apply_adhoc_ddl(
            &mut conn,
            9100,
            "demo_col",
            "CREATE TABLE IF NOT EXISTS zz_audit (i INTEGER);",
        )
        .unwrap();
        let n: i64 = conn
            .query_row("SELECT COUNT(*) FROM zz_audit", [], |row| row.get(0))
            .unwrap();
        assert_eq!(n, 0);
    }
}
