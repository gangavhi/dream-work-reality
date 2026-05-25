//! Live SQLite catalog introspection and validated DDL for ML storage plans (ADR 0005).

use std::collections::BTreeSet;

use rusqlite::Connection;
use serde::{Deserialize, Serialize};

use crate::db::MigrationError;

/// Tables the model must not drop or replace; writes use the approved DSL only.
pub const PROTECTED_TABLES: &[&str] = &[
    "schema_change_log",
    "manual_entry",
    "manual_field",
    "extraction_run",
];

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SqliteColumnInfo {
    pub name: String,
    pub sql_type: String,
    pub not_null: bool,
    pub primary_key: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SqliteTableInfo {
    pub name: String,
    pub columns: Vec<SqliteColumnInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SqliteSchemaSnapshot {
    pub tables: Vec<SqliteTableInfo>,
}

/// Collect user-visible tables and column metadata for the storage planner prompt.
pub fn collect_schema_snapshot(conn: &Connection) -> Result<SqliteSchemaSnapshot, MigrationError> {
    let mut table_names: Vec<String> = Vec::new();
    let mut stmt = conn.prepare(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    )?;
    let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
    for row in rows {
        table_names.push(row?);
    }

    let mut tables = Vec::with_capacity(table_names.len());
    for name in table_names {
        let mut col_stmt = conn.prepare(&format!("PRAGMA table_info(\"{}\")", escape_ident(&name)))?;
        let col_rows = col_stmt.query_map([], |row| {
            Ok(SqliteColumnInfo {
                name: row.get(1)?,
                sql_type: row.get(2)?,
                not_null: row.get::<_, i64>(3)? != 0,
                primary_key: row.get::<_, i64>(5)? != 0,
            })
        })?;
        let mut columns = Vec::new();
        for col in col_rows {
            columns.push(col?);
        }
        tables.push(SqliteTableInfo { name, columns });
    }
    Ok(SqliteSchemaSnapshot { tables })
}

pub fn schema_snapshot_json(conn: &Connection) -> Result<String, MigrationError> {
    let snapshot = collect_schema_snapshot(conn)?;
    serde_json::to_string(&snapshot).map_err(|e| MigrationError::Sqlite(rusqlite::Error::ToSqlConversionFailure(
        Box::new(e),
    )))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProposedColumn {
    pub name: String,
    pub sql_type: String,
    pub nullable: bool,
}

pub fn validate_table_name(name: &str) -> Result<(), String> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err("table name empty".into());
    }
    if !trimmed
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
    {
        return Err(format!("invalid table name: {trimmed}"));
    }
    if !trimmed
        .chars()
        .next()
        .is_some_and(|c| c.is_ascii_lowercase())
    {
        return Err(format!("table name must start with a letter: {trimmed}"));
    }
    if trimmed.len() > 64 {
        return Err(format!("table name too long: {trimmed}"));
    }
    if PROTECTED_TABLES.contains(&trimmed) {
        return Err(format!("protected table cannot be created via planner: {trimmed}"));
    }
    Ok(())
}

pub fn validate_column_name(name: &str) -> Result<(), String> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err("column name empty".into());
    }
    if !trimmed
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
    {
        return Err(format!("invalid column name: {trimmed}"));
    }
    Ok(())
}

pub fn normalize_sql_type(sql_type: &str) -> Result<&'static str, String> {
    match sql_type.trim().to_uppercase().as_str() {
        "TEXT" | "STRING" => Ok("TEXT"),
        "INTEGER" | "INT" => Ok("INTEGER"),
        "REAL" | "FLOAT" | "DOUBLE" => Ok("REAL"),
        other => Err(format!("unsupported sql type: {other}")),
    }
}

pub fn build_create_table_sql(table_name: &str, columns: &[ProposedColumn]) -> Result<String, String> {
    validate_table_name(table_name)?;
    if columns.is_empty() {
        return Err("create_table requires at least one column".into());
    }
    if columns.len() > 32 {
        return Err("create_table exceeds max 32 columns".into());
    }
    let mut seen = BTreeSet::new();
    let mut parts = Vec::new();
    for col in columns {
        validate_column_name(&col.name)?;
        if !seen.insert(col.name.clone()) {
            return Err(format!("duplicate column: {}", col.name));
        }
        let sql_type = normalize_sql_type(&col.sql_type)?;
        let null_sql = if col.nullable { "" } else { " NOT NULL" };
        parts.push(format!(
            "\"{}\" {}{}",
            escape_ident(&col.name),
            sql_type,
            null_sql
        ));
    }
    Ok(format!(
        "CREATE TABLE IF NOT EXISTS \"{}\" ({});",
        escape_ident(table_name),
        parts.join(", ")
    ))
}

pub fn build_add_column_sql(
    table_name: &str,
    column_name: &str,
    sql_type: &str,
    nullable: bool,
) -> Result<String, String> {
    validate_table_name(table_name)?;
    if PROTECTED_TABLES.contains(&table_name) {
        return Err(format!(
            "protected table cannot be altered via planner: {table_name}"
        ));
    }
    validate_column_name(column_name)?;
    let sql_type = normalize_sql_type(sql_type)?;
    let null_sql = if nullable { "" } else { " NOT NULL" };
    Ok(format!(
        "ALTER TABLE \"{}\" ADD COLUMN \"{}\" {}{};",
        escape_ident(table_name),
        escape_ident(column_name),
        sql_type,
        null_sql
    ))
}

fn escape_ident(value: &str) -> String {
    value.replace('"', "\"\"")
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    #[test]
    fn snapshot_lists_core_tables() {
        let mut conn = Connection::open_in_memory().unwrap();
        crate::db::apply_core_migrations(&mut conn).unwrap();
        let snapshot = collect_schema_snapshot(&conn).unwrap();
        let names: Vec<_> = snapshot.tables.iter().map(|t| t.name.as_str()).collect();
        assert!(names.contains(&"manual_entry"));
        assert!(names.contains(&"manual_field"));
    }

    #[test]
    fn rejects_protected_create_table() {
        let err = build_create_table_sql(
            "manual_entry",
            &[ProposedColumn {
                name: "x".into(),
                sql_type: "TEXT".into(),
                nullable: true,
            }],
        )
        .unwrap_err();
        assert!(err.contains("protected"));
    }
}
