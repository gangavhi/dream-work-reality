//! Stage 2 local-ML storage routing: table fit, schema proposals, and row plans (ADR 0005).

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::inference::{generate_constrained_json, InferenceError};
use crate::storage_schema::SqliteSchemaSnapshot;

pub const STORAGE_PLANNER_ENGINE_ID: &str = "llm.storage_planner.v1";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StorageOperationKind {
    /// Model-selected reusable profile slot (`manual_field`).
    UpsertManualField,
    /// Document-specific extension slot (`manual_field`).
    UpsertExtensionField,
    /// Insert one row into an existing or newly created dynamic table.
    InsertRow,
    /// Declared in schema_actions; executed via trusted DDL, not as a row op.
    CreateTable,
    /// Declared in schema_actions; executed via trusted DDL.
    AddColumn,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StorageTargetDecision {
    /// `use_existing_table` or `create_table`
    pub decision: String,
    pub table_name: String,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SchemaColumn {
    pub name: String,
    pub sql_type: String,
    pub nullable: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SchemaAction {
    /// `create_table` or `add_column`
    pub op: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub table_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub column_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sql_type: Option<String>,
    #[serde(default)]
    pub nullable: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub columns: Option<Vec<SchemaColumn>>,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StorageOperation {
    pub op: StorageOperationKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub person_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub table_name: Option<String>,
    pub key: String,
    pub value: String,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub row_values: BTreeMap<String, String>,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StoragePlanSummary {
    pub canonical_count: u32,
    pub extension_count: u32,
    pub skipped_empty: u32,
    pub planner_engine: String,
    pub planner_status: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StoragePlan {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub storage_target: Option<StorageTargetDecision>,
    #[serde(default)]
    pub schema_actions: Vec<SchemaAction>,
    pub operations: Vec<StorageOperation>,
    pub summary: StoragePlanSummary,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PlanStorageRequest {
    #[serde(default)]
    pub fields: BTreeMap<String, String>,
    #[serde(default)]
    pub person_id: Option<String>,
    #[serde(default)]
    pub profile_schema_keys: Option<Vec<String>>,
    #[serde(default)]
    pub model_path: Option<String>,
    #[serde(default)]
    pub document_type: Option<String>,
    /// Live SQLite catalog injected by the host before inference.
    #[serde(default)]
    pub sqlite_schema: Option<SqliteSchemaSnapshot>,
}

#[derive(Debug, Clone, Deserialize)]
struct LlmStoragePlan {
    #[serde(default)]
    storage_target: Option<StorageTargetDecision>,
    #[serde(default)]
    schema_actions: Vec<SchemaAction>,
    #[serde(default)]
    operations: Vec<StorageOperation>,
}

/// Build a storage plan without executing writes. Fail-closed when the model is missing.
pub fn plan_storage(req: &PlanStorageRequest) -> StoragePlan {
    let skipped_empty = req
        .fields
        .values()
        .filter(|value| value.trim().is_empty())
        .count() as u32;
    let Some(model_path) = req.model_path.as_deref().filter(|p| !p.trim().is_empty()) else {
        return failed_plan(skipped_empty, "storage_planner_model_missing");
    };
    if !std::path::Path::new(model_path).is_file() {
        return failed_plan(skipped_empty, "storage_planner_model_missing");
    }

    match generate_constrained_json(model_path, &storage_prompt(req), 256)
        .and_then(|json| parse_storage_plan(&json))
    {
        Ok(parsed) => {
            let mut operations = parsed.operations;
            operations.retain(|op| match op.op {
                StorageOperationKind::InsertRow => !op.row_values.is_empty(),
                StorageOperationKind::UpsertManualField
                | StorageOperationKind::UpsertExtensionField => {
                    !op.key.trim().is_empty() && !op.value.trim().is_empty()
                }
                StorageOperationKind::CreateTable | StorageOperationKind::AddColumn => false,
            });
            operations.sort_by(|a, b| a.key.cmp(&b.key));
            let canonical_count = operations
                .iter()
                .filter(|op| op.op == StorageOperationKind::UpsertManualField)
                .count() as u32;
            let extension_count = operations
                .iter()
                .filter(|op| op.op == StorageOperationKind::UpsertExtensionField)
                .count() as u32;
            StoragePlan {
                storage_target: parsed.storage_target,
                schema_actions: parsed.schema_actions,
                operations,
                summary: StoragePlanSummary {
                    canonical_count,
                    extension_count,
                    skipped_empty,
                    planner_engine: STORAGE_PLANNER_ENGINE_ID.to_string(),
                    planner_status: "storage_planner_active".to_string(),
                },
            }
        }
        Err(err) => failed_plan(
            skipped_empty,
            &format!("storage_planner_generation_failed:{}", status_reason(&err)),
        ),
    }
}

fn parse_storage_plan(json: &str) -> Result<LlmStoragePlan, InferenceError> {
    serde_json::from_str::<LlmStoragePlan>(json)
        .map_err(|e| InferenceError::Session(format!("invalid storage plan JSON: {e}")))
}

fn storage_prompt(req: &PlanStorageRequest) -> String {
    let fields_json = serde_json::to_string(&req.fields).unwrap_or_else(|_| "{}".to_string());
    let person_id = req.person_id.as_deref().unwrap_or("");
    let document_type = req.document_type.as_deref().unwrap_or("unknown");
    let profile_keys = req
        .profile_schema_keys
        .as_ref()
        .map(|keys| keys.join(", "))
        .unwrap_or_else(|| "open vocabulary".to_string());
    let schema_json = req
        .sqlite_schema
        .as_ref()
        .and_then(|s| serde_json::to_string(s).ok())
        .unwrap_or_else(|| r#"{"tables":[]}"#.to_string());

    format!(
        r#"You are a SQLite storage planner. Given extracted document fields and the LIVE database schema, decide:
1) whether data fits an existing table (usually manual_field for profile facts) or needs a new table;
2) if a new table is needed, emit schema_actions to create it;
3) emit row operations to persist values.

Rules:
- Return only JSON.
- Use exactly this shape:
{{
  "storage_target": {{"decision":"use_existing_table|create_table","table_name":"snake_case","reason":"short"}},
  "schema_actions": [
    {{"op":"create_table","table_name":"snake_case","columns":[{{"name":"col","sql_type":"TEXT|INTEGER|REAL","nullable":true}}],"reason":"short"}},
    {{"op":"add_column","table_name":"snake_case","column_name":"col","sql_type":"TEXT","nullable":true,"reason":"short"}}
  ],
  "operations": [
    {{"op":"upsert_manual_field|upsert_extension_field","person_id":"id_or_empty","key":"field_key","value":"v","reason":"short"}},
    {{"op":"insert_row","table_name":"snake_case","row_values":{{"col":"v"}},"key":"row","value":"","reason":"short"}}
  ]
}}
- Prefer manual_entry/manual_field for reusable identity/profile facts when columns already match.
- Use create_table only when the extracted dataset is tabular/document-specific and does not map cleanly to manual_field.
- Never target protected tables: schema_change_log, manual_entry, manual_field, extraction_run (writes only via operations above).
- Do not invent field values not present in extracted fields.
- sql_type must be TEXT, INTEGER, or REAL.
- If uncertain, use_existing_table on manual_field with upsert_extension_field.

Document type: {document_type}
Person id: {person_id}
Profile schema keys: {profile_keys}
Live SQLite schema JSON:
{schema_json}
Extracted fields JSON:
{fields_json}"#
    )
}

fn failed_plan(skipped_empty: u32, status: &str) -> StoragePlan {
    StoragePlan {
        storage_target: None,
        schema_actions: Vec::new(),
        operations: Vec::new(),
        summary: StoragePlanSummary {
            canonical_count: 0,
            extension_count: 0,
            skipped_empty,
            planner_engine: STORAGE_PLANNER_ENGINE_ID.to_string(),
            planner_status: status.to_string(),
        },
    }
}

fn status_reason(err: &InferenceError) -> String {
    err.to_string()
        .chars()
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_model_fails_closed() {
        let mut fields = BTreeMap::new();
        fields.insert("first_name".into(), "Alex".into());
        let plan = plan_storage(&PlanStorageRequest {
            fields,
            person_id: Some("p1".into()),
            profile_schema_keys: None,
            model_path: None,
            document_type: None,
            sqlite_schema: None,
        });
        assert!(plan.operations.is_empty());
        assert_eq!(plan.summary.planner_status, "storage_planner_model_missing");
    }
}
