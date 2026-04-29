use std::collections::HashMap;

use crate::ingestion::ManualEntry;
use crate::ingestion::ManualField;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RepositoryError {
    NotFound,
    StorageFailure,
}

pub trait EntryRepository {
    fn save_manual_entry(&mut self, entry: ManualEntry) -> Result<(), RepositoryError>;
    fn get_manual_entry(&self, id: &str) -> Result<ManualEntry, RepositoryError>;
    fn list_profile_keys(&self) -> Vec<(String, String)> {
        // (entry_id, profile_key)
        let _ = self; // default: unknown
        vec![]
    }
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

    fn list_profile_keys(&self) -> Vec<(String, String)> {
        let mut out: Vec<(String, String)> = vec![];
        for (id, entry) in &self.manual_entries {
            let pk = entry
                .fields
                .iter()
                .find(|f| f.key == "profile_key")
                .map(|f| f.value.trim().to_string())
                .filter(|s| !s.is_empty());
            if let Some(pk) = pk {
                out.push((id.clone(), pk));
            }
        }
        out.sort_by(|a, b| a.0.cmp(&b.0));
        out
    }
}

impl InMemoryRepository {
    pub fn manual_entry_count(&self) -> usize {
        self.manual_entries.len()
    }
}

pub struct SqliteRepository {
    conn: rusqlite::Connection,
}

impl SqliteRepository {
    pub fn open(path: &std::path::Path) -> Result<Self, RepositoryError> {
        let conn = rusqlite::Connection::open(path).map_err(|_| RepositoryError::StorageFailure)?;
        let repo = Self { conn };
        repo.init_schema()?;
        Ok(repo)
    }

    fn init_schema(&self) -> Result<(), RepositoryError> {
        self.conn
            .execute_batch(
                r#"
                PRAGMA foreign_keys = ON;

                CREATE TABLE IF NOT EXISTS manual_entries (
                    id TEXT PRIMARY KEY
                );

                CREATE TABLE IF NOT EXISTS manual_fields (
                    entry_id TEXT NOT NULL,
                    key TEXT NOT NULL,
                    value TEXT NOT NULL,
                    PRIMARY KEY(entry_id, key),
                    FOREIGN KEY(entry_id) REFERENCES manual_entries(id) ON DELETE CASCADE
                );
                "#,
            )
            .map_err(|_| RepositoryError::StorageFailure)?;
        Ok(())
    }
}

impl EntryRepository for SqliteRepository {
    fn save_manual_entry(&mut self, entry: ManualEntry) -> Result<(), RepositoryError> {
        let tx = self
            .conn
            .transaction()
            .map_err(|_| RepositoryError::StorageFailure)?;

        tx.execute(
            "INSERT INTO manual_entries (id) VALUES (?1) ON CONFLICT(id) DO NOTHING",
            [&entry.id],
        )
        .map_err(|_| RepositoryError::StorageFailure)?;

        for f in entry.fields {
            let key = f.key.trim();
            let value = f.value.trim();
            if key.is_empty() || value.is_empty() {
                continue;
            }
            tx.execute(
                r#"
                INSERT INTO manual_fields (entry_id, key, value)
                VALUES (?1, ?2, ?3)
                ON CONFLICT(entry_id, key) DO UPDATE SET value = excluded.value
                "#,
                (&entry.id, key, value),
            )
            .map_err(|_| RepositoryError::StorageFailure)?;
        }

        tx.commit().map_err(|_| RepositoryError::StorageFailure)?;
        Ok(())
    }

    fn get_manual_entry(&self, id: &str) -> Result<ManualEntry, RepositoryError> {
        let exists: bool = self
            .conn
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM manual_entries WHERE id = ?1)",
                [id],
                |row| row.get::<_, i64>(0).map(|v| v != 0),
            )
            .map_err(|_| RepositoryError::StorageFailure)?;
        if !exists {
            return Err(RepositoryError::NotFound);
        }

        let mut stmt = self
            .conn
            .prepare("SELECT key, value FROM manual_fields WHERE entry_id = ?1")
            .map_err(|_| RepositoryError::StorageFailure)?;
        let rows = stmt
            .query_map([id], |row| {
                Ok(ManualField {
                    key: row.get(0)?,
                    value: row.get(1)?,
                })
            })
            .map_err(|_| RepositoryError::StorageFailure)?;

        let mut fields = Vec::new();
        for r in rows {
            fields.push(r.map_err(|_| RepositoryError::StorageFailure)?);
        }

        Ok(ManualEntry {
            id: id.to_string(),
            fields,
        })
    }

    fn list_profile_keys(&self) -> Vec<(String, String)> {
        let Ok(mut stmt) = self.conn.prepare(
            r#"
            SELECT mf.entry_id, mf.value
            FROM manual_fields mf
            WHERE mf.key = 'profile_key'
            ORDER BY mf.entry_id ASC
            "#,
        ) else {
            return vec![];
        };

        let Ok(rows) = stmt.query_map([], |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))) else {
            return vec![];
        };

        let mut out: Vec<(String, String)> = vec![];
        for r in rows.flatten() {
            let (id, pk) = r;
            let pk2 = pk.trim().to_string();
            if !pk2.is_empty() {
                out.push((id, pk2));
            }
        }
        out
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
