//! Stage 2 local-ML storage routing: route extracted fields without canonical-key rules.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::inference::{generate_constrained_json, InferenceError};

pub const STORAGE_PLANNER_ENGINE_ID: &str = "llm.storage_planner.v1";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StorageOperationKind {
    /// Model-selected reusable profile slot.
    UpsertManualField,
    /// Model-selected document-specific extension slot.
    UpsertExtensionField,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StorageOperation {
    pub op: StorageOperationKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub person_id: Option<String>,
    pub key: String,
    pub value: String,
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
}

#[derive(Debug, Clone, Deserialize)]
struct LlmStoragePlan {
    #[serde(default)]
    operations: Vec<StorageOperation>,
}

/// Build a storage plan without executing writes. This is fail-closed: no model, no plan.
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

    match generate_constrained_json(model_path, &storage_prompt(req), 384)
        .and_then(|json| parse_storage_plan(&json))
    {
        Ok(mut operations) => {
            operations.retain(|op| !op.key.trim().is_empty() && !op.value.trim().is_empty());
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

fn parse_storage_plan(json: &str) -> Result<Vec<StorageOperation>, InferenceError> {
    serde_json::from_str::<LlmStoragePlan>(json)
        .map(|plan| plan.operations)
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
        .unwrap_or_else(|| {
            "open vocabulary; infer durable profile fields vs document extension fields".to_string()
        });

    format!(
        r#"Plan SQLite persistence for extracted document fields.

Rules:
- Return only JSON.
- Use exactly this shape:
  {{"operations":[{{"op":"upsert_manual_field|upsert_extension_field","person_id":"string_or_empty","key":"field_key","value":"field_value","reason":"short_model_reason"}}]}}
- Choose upsert_manual_field only for reusable identity/profile facts.
- Choose upsert_extension_field for document-specific, issuer-specific, payload, or one-off facts.
- Do not invent fields or values.
- Use the provided person_id when present.

Document type: {document_type}
Person id: {person_id}
Known schema guidance: {profile_keys}
Extracted fields JSON:
{fields_json}"#
    )
}

fn failed_plan(skipped_empty: u32, status: &str) -> StoragePlan {
    StoragePlan {
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
        fields.insert("dl_number".into(), "D123".into());
        let plan = plan_storage(&PlanStorageRequest {
            fields,
            person_id: Some("p1".into()),
            profile_schema_keys: None,
            model_path: None,
            document_type: None,
        });
        assert!(plan.operations.is_empty());
        assert_eq!(plan.summary.planner_status, "storage_planner_model_missing");
    }

    #[test]
    fn skips_empty_values() {
        let mut fields = BTreeMap::new();
        fields.insert("email".into(), "  ".into());
        let plan = plan_storage(&PlanStorageRequest {
            fields,
            person_id: None,
            profile_schema_keys: None,
            model_path: None,
            document_type: None,
        });
        assert!(plan.operations.is_empty());
        assert_eq!(plan.summary.skipped_empty, 1);
    }
}
