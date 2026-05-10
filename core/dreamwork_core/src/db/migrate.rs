use std::collections::HashSet;
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection};
use sha2::{Digest, Sha256};

#[derive(Debug)]
pub enum MigrationError {
    Sqlite(rusqlite::Error),
    ChecksumMismatch {
        id: i64,
        expected: String,
        stored: String,
    },
}

impl std::fmt::Display for MigrationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MigrationError::Sqlite(e) => write!(f, "{e}"),
            MigrationError::ChecksumMismatch {
                id,
                expected,
                stored,
            } => write!(
                f,
                "migration {id} checksum mismatch (stored {stored}, expected {expected})"
            ),
        }
    }
}

impl std::error::Error for MigrationError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            MigrationError::Sqlite(e) => Some(e),
            _ => None,
        }
    }
}

impl From<rusqlite::Error> for MigrationError {
    fn from(e: rusqlite::Error) -> Self {
        MigrationError::Sqlite(e)
    }
}

pub fn checksum_sql(sql: &str) -> String {
    let mut h = Sha256::new();
    h.update(sql.trim().as_bytes());
    hex::encode(h.finalize())
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

pub fn ensure_bootstrap_schema(conn: &Connection) -> Result<(), MigrationError> {
    conn.execute_batch(
        r#"
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS schema_change_log (
            migration_id INTEGER PRIMARY KEY NOT NULL,
            migration_name TEXT NOT NULL,
            applied_at_ms INTEGER NOT NULL,
            checksum TEXT NOT NULL
        );
        "#,
    )?;
    Ok(())
}

fn applied_migration_ids(conn: &Connection) -> Result<HashSet<i64>, rusqlite::Error> {
    let mut stmt = conn.prepare("SELECT migration_id FROM schema_change_log")?;
    let rows = stmt.query_map([], |row| row.get::<_, i64>(0))?;
    rows.collect()
}

pub struct StaticMigration {
    pub id: i64,
    pub name: &'static str,
    pub up_sql: &'static str,
}

pub const CORE_MIGRATIONS: &[StaticMigration] = &[
    StaticMigration {
        id: 1,
        name: "manual_entry_v1",
        up_sql: r#"
        CREATE TABLE IF NOT EXISTS manual_entry (
            id TEXT PRIMARY KEY NOT NULL
        );

        CREATE TABLE IF NOT EXISTS manual_field (
            entry_id TEXT NOT NULL REFERENCES manual_entry(id) ON DELETE CASCADE,
            field_key TEXT NOT NULL,
            value TEXT NOT NULL,
            PRIMARY KEY (entry_id, field_key)
        );
        "#,
    },
    StaticMigration {
        id: 2,
        name: "extraction_run_v1",
        up_sql: r#"
        CREATE TABLE IF NOT EXISTS extraction_run (
            id TEXT PRIMARY KEY NOT NULL,
            created_at_ms INTEGER NOT NULL,
            engine_id TEXT NOT NULL,
            model_revision TEXT NOT NULL,
            language_tag TEXT NOT NULL,
            document_json TEXT NOT NULL
        );
        "#,
    },
];

fn verify_checksum(conn: &Connection, m: &StaticMigration) -> Result<(), MigrationError> {
    let stored: String = conn.query_row(
        "SELECT checksum FROM schema_change_log WHERE migration_id = ?1",
        params![m.id],
        |row| row.get(0),
    )?;
    let expected = checksum_sql(m.up_sql);
    if stored != expected {
        return Err(MigrationError::ChecksumMismatch {
            id: m.id,
            expected,
            stored,
        });
    }
    Ok(())
}

pub fn apply_core_migrations(conn: &mut Connection) -> Result<(), MigrationError> {
    ensure_bootstrap_schema(conn)?;
    let applied = applied_migration_ids(conn)?;
    for m in CORE_MIGRATIONS {
        if applied.contains(&m.id) {
            verify_checksum(conn, m)?;
            continue;
        }
        let tx = conn.transaction()?;
        tx.execute_batch(m.up_sql)?;
        tx.execute(
            "INSERT INTO schema_change_log (migration_id, migration_name, applied_at_ms, checksum)
             VALUES (?1, ?2, ?3, ?4)",
            params![m.id, m.name, now_ms(), checksum_sql(m.up_sql)],
        )?;
        tx.commit()?;
    }
    Ok(())
}

/// Transactional DDL with an audit row — used when dynamic schema proposals land (ADR 0005).
pub fn apply_adhoc_ddl(
    conn: &mut Connection,
    migration_id: i64,
    migration_name: &str,
    ddl: &str,
) -> Result<(), MigrationError> {
    let cs = checksum_sql(ddl);
    let tx = conn.transaction()?;
    tx.execute_batch(ddl)?;
    tx.execute(
        "INSERT INTO schema_change_log (migration_id, migration_name, applied_at_ms, checksum)
         VALUES (?1, ?2, ?3, ?4)",
        params![migration_id, migration_name, now_ms(), cs],
    )?;
    tx.commit()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    #[test]
    fn core_migrations_apply_once_and_record_checksum() {
        let mut conn = Connection::open_in_memory().unwrap();
        apply_core_migrations(&mut conn).unwrap();
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM schema_change_log WHERE migration_id = 1",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(count, 1);
        apply_core_migrations(&mut conn).unwrap();
        let count2: i64 = conn
            .query_row("SELECT COUNT(*) FROM schema_change_log", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(count2, CORE_MIGRATIONS.len() as i64);
    }

    #[test]
    fn core_migration_2_creates_extraction_run_table() {
        let mut conn = Connection::open_in_memory().unwrap();
        apply_core_migrations(&mut conn).unwrap();
        let n: i64 = conn
            .query_row("SELECT COUNT(*) FROM extraction_run", [], |row| row.get(0))
            .unwrap();
        assert_eq!(n, 0);
        let log_rows: i64 = conn
            .query_row("SELECT COUNT(*) FROM schema_change_log", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(log_rows, 2);
    }

    #[test]
    fn adhoc_ddl_inserts_log_row() {
        let mut conn = Connection::open_in_memory().unwrap();
        apply_core_migrations(&mut conn).unwrap();
        apply_adhoc_ddl(
            &mut conn,
            9001,
            "test_extra_col",
            "CREATE TABLE IF NOT EXISTS demo_x (i INTEGER);",
        )
        .unwrap();
        let name: String = conn
            .query_row(
                "SELECT migration_name FROM schema_change_log WHERE migration_id = 9001",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(name, "test_extra_col");
    }
}
