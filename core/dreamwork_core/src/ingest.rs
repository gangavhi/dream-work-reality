//! JSON ingest helpers for FFI / HTTP (Stage 2 + Stage 3).

use std::collections::BTreeMap;

use serde::Deserialize;

use crate::entity_resolution::{self, ExistingPerson, ResolvePersonResult};
use crate::runtime;
use crate::storage_apply::ApplyStoragePlanResult;
use crate::storage_routing::{PlanStorageRequest, StoragePlan};
use crate::storage_schema::SqliteSchemaSnapshot;

#[derive(Debug, Clone, Deserialize)]
pub struct ResolvePersonJsonRequest {
    #[serde(default)]
    pub fields: BTreeMap<String, String>,
    #[serde(default)]
    pub existing_persons: Option<Vec<ExistingPerson>>,
}

/// Resolve person from JSON request; loads repository persons when `existing_persons` is omitted.
pub fn resolve_person_from_json(json: &str) -> Result<ResolvePersonResult, String> {
    let req: ResolvePersonJsonRequest =
        serde_json::from_str(json).map_err(|e| format!("invalid JSON: {e}"))?;

    let existing = match req.existing_persons {
        Some(persons) => persons,
        None => runtime::list_existing_persons_for_resolution(),
    };

    Ok(entity_resolution::resolve_person(&req.fields, &existing))
}

#[derive(Debug, Clone, Deserialize)]
pub struct PlanStorageJsonRequest {
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
    #[serde(default)]
    pub sqlite_schema: Option<SqliteSchemaSnapshot>,
}

pub fn plan_storage_from_json(json: &str) -> Result<StoragePlan, String> {
    let req: PlanStorageJsonRequest =
        serde_json::from_str(json).map_err(|e| format!("invalid JSON: {e}"))?;
    let sqlite_schema = req
        .sqlite_schema
        .or_else(runtime::peek_sqlite_schema_snapshot);
    Ok(crate::storage_routing::plan_storage(&PlanStorageRequest {
        fields: req.fields,
        person_id: req.person_id,
        profile_schema_keys: req.profile_schema_keys,
        model_path: req.model_path,
        document_type: req.document_type,
        sqlite_schema,
    }))
}

pub fn apply_storage_plan_from_json(plan_json: &str) -> Result<ApplyStoragePlanResult, String> {
    let plan: StoragePlan =
        serde_json::from_str(plan_json).map_err(|e| format!("invalid storage plan JSON: {e}"))?;
    Ok(runtime::apply_storage_plan(&plan))
}

/// Serialize [`ResolvePersonResult`] to JSON for hosts.
pub fn resolve_person_result_to_json(result: &ResolvePersonResult) -> Option<String> {
    serde_json::to_string(result).ok()
}

pub fn storage_plan_to_json(plan: &StoragePlan) -> Option<String> {
    serde_json::to_string(plan).ok()
}

pub fn apply_storage_plan_result_to_json(result: &ApplyStoragePlanResult) -> Option<String> {
    serde_json::to_string(result).ok()
}
