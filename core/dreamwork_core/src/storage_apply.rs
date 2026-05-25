//! Execute ML storage plans inside a single SQLite transaction (ADR 0005).

use std::collections::BTreeMap;

use rusqlite::{params, Connection};
use serde::Serialize;

use crate::db::{apply_adhoc_ddl, checksum_sql, MigrationError};
use crate::ingestion::{ManualEntry, ManualField};
use crate::storage_routing::{
    SchemaAction, StorageOperation, StorageOperationKind, StoragePlan,
};
use crate::storage_schema::{
    build_add_column_sql, build_create_table_sql, validate_table_name, ProposedColumn,
};

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct ApplyStoragePlanResult {
    pub applied: bool,
    pub status: String,
    pub ddl_applied: u32,
    pub rows_written: u32,
    pub profile_fields_written: u32,
}

pub fn apply_storage_plan(conn: &mut Connection, plan: &StoragePlan) -> ApplyStoragePlanResult {
    if plan.summary.planner_status != "storage_planner_active" {
        return ApplyStoragePlanResult {
            applied: false,
            status: format!("storage_apply_skipped:{}", plan.summary.planner_status),
            ddl_applied: 0,
            rows_written: 0,
            profile_fields_written: 0,
        };
    }

    match apply_storage_plan_inner(conn, plan) {
        Ok(stats) => ApplyStoragePlanResult {
            applied: true,
            status: "storage_apply_active".to_string(),
            ddl_applied: stats.ddl_applied,
            rows_written: stats.rows_written,
            profile_fields_written: stats.profile_fields_written,
        },
        Err(err) => ApplyStoragePlanResult {
            applied: false,
            status: format!("storage_apply_failed:{}", sanitize_status(&err.to_string())),
            ddl_applied: 0,
            rows_written: 0,
            profile_fields_written: 0,
        },
    }
}

struct ApplyStats {
    ddl_applied: u32,
    rows_written: u32,
    profile_fields_written: u32,
}

fn apply_storage_plan_inner(
    conn: &mut Connection,
    plan: &StoragePlan,
) -> Result<ApplyStats, String> {
    let ddl_batch = compile_ddl_batch(&plan.schema_actions)?;
    let mut stats = ApplyStats {
        ddl_applied: 0,
        rows_written: 0,
        profile_fields_written: 0,
    };

    if !ddl_batch.is_empty() {
        let migration_id = next_adhoc_migration_id(conn).map_err(|e| e.to_string())?;
        let migration_name = plan
            .storage_target
            .as_ref()
            .map(|t| format!("ml_storage_{}", t.table_name))
            .unwrap_or_else(|| "ml_storage_schema".to_string());
        apply_adhoc_ddl(conn, migration_id, &migration_name, &ddl_batch)
            .map_err(|e| e.to_string())?;
        stats.ddl_applied = plan.schema_actions.len() as u32;
    }

    let tx = conn.transaction().map_err(|e| e.to_string())?;

    for op in &plan.operations {
        match op.op {
            StorageOperationKind::UpsertManualField | StorageOperationKind::UpsertExtensionField => {
                let person_id = op
                    .person_id
                    .as_deref()
                    .filter(|id| !id.trim().is_empty())
                    .ok_or_else(|| format!("missing person_id for key {}", op.key))?;
                upsert_manual_field(&tx, person_id, &op.key, &op.value)?;
                stats.profile_fields_written += 1;
            }
            StorageOperationKind::InsertRow => {
                let table = op
                    .table_name
                    .as_deref()
                    .ok_or_else(|| format!("insert_row missing table for key {}", op.key))?;
                validate_table_name(table)?;
                insert_dynamic_row(&tx, table, &op.row_values)?;
                stats.rows_written += 1;
            }
            StorageOperationKind::CreateTable | StorageOperationKind::AddColumn => {
                // DDL handled in schema_actions batch above.
            }
        }
    }

    tx.commit().map_err(|e| e.to_string())?;
    Ok(stats)
}

fn compile_ddl_batch(actions: &[SchemaAction]) -> Result<String, String> {
    let mut parts = Vec::new();
    for action in actions {
        match action.op.as_str() {
            "create_table" => {
                let table = action
                    .table_name
                    .as_deref()
                    .ok_or_else(|| "create_table missing table_name".to_string())?;
                let columns = action
                    .columns
                    .as_ref()
                    .ok_or_else(|| "create_table missing columns".to_string())?;
                let proposed: Vec<ProposedColumn> = columns
                    .iter()
                    .map(|c| ProposedColumn {
                        name: c.name.clone(),
                        sql_type: c.sql_type.clone(),
                        nullable: c.nullable,
                    })
                    .collect();
                parts.push(build_create_table_sql(table, &proposed)?);
            }
            "add_column" => {
                let table = action
                    .table_name
                    .as_deref()
                    .ok_or_else(|| "add_column missing table_name".to_string())?;
                let column = action
                    .column_name
                    .as_deref()
                    .ok_or_else(|| "add_column missing column_name".to_string())?;
                let sql_type = action
                    .sql_type
                    .as_deref()
                    .ok_or_else(|| "add_column missing sql_type".to_string())?;
                parts.push(build_add_column_sql(
                    table,
                    column,
                    sql_type,
                    action.nullable,
                )?);
            }
            other => return Err(format!("unsupported schema action: {other}")),
        }
    }
    Ok(parts.join("\n"))
}

fn next_adhoc_migration_id(conn: &Connection) -> Result<i64, MigrationError> {
    let base: i64 = conn.query_row(
        "SELECT COALESCE(MAX(migration_id), 9999) FROM schema_change_log WHERE migration_id >= 10000",
        [],
        |row| row.get(0),
    )?;
    Ok(base + 1)
}

fn upsert_manual_field(
    tx: &rusqlite::Transaction<'_>,
    person_id: &str,
    key: &str,
    value: &str,
) -> Result<(), String> {
    tx.execute(
        "INSERT OR IGNORE INTO manual_entry (id) VALUES (?1)",
        params![person_id],
    )
    .map_err(|e| e.to_string())?;
    tx.execute(
        "INSERT INTO manual_field (entry_id, field_key, value) VALUES (?1, ?2, ?3)
         ON CONFLICT(entry_id, field_key) DO UPDATE SET value = excluded.value",
        params![person_id, key, value],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

fn insert_dynamic_row(
    tx: &rusqlite::Transaction<'_>,
    table_name: &str,
    values: &BTreeMap<String, String>,
) -> Result<(), String> {
    if values.is_empty() {
        return Err("insert_row requires row_values".into());
    }
    validate_table_name(table_name)?;
    let cols: Vec<&String> = values.keys().collect();
    let placeholders: Vec<String> = (1..=cols.len()).map(|i| format!("?{i}")).collect();
    let col_sql: Vec<String> = cols
        .iter()
        .map(|c| format!("\"{}\"", c.replace('"', "\"\"")))
        .collect();
    let sql = format!(
        "INSERT INTO \"{}\" ({}) VALUES ({});",
        table_name.replace('"', "\"\""),
        col_sql.join(", "),
        placeholders.join(", ")
    );
    let mut params_vec: Vec<Box<dyn rusqlite::ToSql>> = Vec::new();
    for key in &cols {
        params_vec.push(Box::new(values[*key].clone()));
    }
    let param_refs: Vec<&dyn rusqlite::ToSql> = params_vec.iter().map(|p| p.as_ref()).collect();
    tx.execute(&sql, param_refs.as_slice())
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// Convenience for hosts/tests: apply plan from [`ManualEntry`] field maps.
pub fn manual_entry_from_profile_ops(
    person_id: &str,
    operations: &[StorageOperation],
) -> ManualEntry {
    let mut fields = Vec::new();
    for op in operations {
        if matches!(
            op.op,
            StorageOperationKind::UpsertManualField | StorageOperationKind::UpsertExtensionField
        ) {
            fields.push(ManualField {
                key: op.key.clone(),
                value: op.value.clone(),
            });
        }
    }
    ManualEntry {
        id: person_id.to_string(),
        fields,
    }
}

fn sanitize_status(raw: &str) -> String {
    raw.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.') {
                c.to_ascii_lowercase()
            } else {
                '_'
            }
        })
        .collect::<String>()
        .trim_matches('_')
        .chars()
        .take(96)
        .collect()
}

#[allow(dead_code)]
fn ddl_checksum(sql: &str) -> String {
    checksum_sql(sql)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage_routing::{
        PlanStorageRequest, SchemaAction, SchemaColumn, StoragePlanSummary, StorageTargetDecision,
    };
    use crate::storage_routing::{plan_storage, StorageOperation, StorageOperationKind};
    use rusqlite::Connection;

    #[test]
    fn apply_executes_create_table_and_insert_row() {
        let mut conn = Connection::open_in_memory().unwrap();
        crate::db::apply_core_migrations(&mut conn).unwrap();
        let plan = StoragePlan {
            storage_target: Some(StorageTargetDecision {
                decision: "create_table".into(),
                table_name: "utility_bill_facts".into(),
                reason: "tabular utility fields".into(),
            }),
            schema_actions: vec![SchemaAction {
                op: "create_table".into(),
                table_name: Some("utility_bill_facts".into()),
                column_name: None,
                sql_type: None,
                nullable: true,
                columns: Some(vec![
                    SchemaColumn {
                        name: "account_number".into(),
                        sql_type: "TEXT".into(),
                        nullable: false,
                    },
                    SchemaColumn {
                        name: "amount_due".into(),
                        sql_type: "TEXT".into(),
                        nullable: true,
                    },
                ]),
                reason: "new fact table".into(),
            }],
            operations: vec![StorageOperation {
                op: StorageOperationKind::InsertRow,
                person_id: None,
                table_name: Some("utility_bill_facts".into()),
                key: "row".into(),
                value: String::new(),
                row_values: BTreeMap::from([
                    ("account_number".into(), "123".into()),
                    ("amount_due".into(), "$10".into()),
                ]),
                reason: "persist scan".into(),
            }],
            summary: StoragePlanSummary {
                canonical_count: 0,
                extension_count: 0,
                skipped_empty: 0,
                planner_engine: "test".into(),
                planner_status: "storage_planner_active".into(),
            },
        };
        let result = apply_storage_plan(&mut conn, &plan);
        assert!(result.applied, "status={}", result.status);
        let n: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM utility_bill_facts WHERE account_number = '123'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(n, 1);
    }

    #[test]
    fn missing_model_plan_not_applied() {
        let mut conn = Connection::open_in_memory().unwrap();
        crate::db::apply_core_migrations(&mut conn).unwrap();
        let plan = plan_storage(&PlanStorageRequest {
            fields: BTreeMap::from([("a".into(), "b".into())]),
            person_id: None,
            profile_schema_keys: None,
            model_path: None,
            document_type: None,
            sqlite_schema: None,
        });
        let result = apply_storage_plan(&mut conn, &plan);
        assert!(!result.applied);
        assert!(result.status.contains("skipped"));
    }
}
