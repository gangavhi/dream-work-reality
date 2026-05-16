//! JSON ingest helpers for FFI / HTTP (Stage 2 + Stage 3).

use std::collections::BTreeMap;

use serde::Deserialize;

use crate::entity_resolution::{
    self, ExistingPerson, ResolvePersonResult,
};
use crate::runtime;
use crate::storage_routing::{PlanStorageRequest, StoragePlan};

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
}

pub fn plan_storage_from_json(json: &str) -> Result<StoragePlan, String> {
    let req: PlanStorageJsonRequest =
        serde_json::from_str(json).map_err(|e| format!("invalid JSON: {e}"))?;
    Ok(crate::storage_routing::plan_storage(&PlanStorageRequest {
        fields: req.fields,
        person_id: req.person_id,
        profile_schema_keys: req.profile_schema_keys,
    }))
}

/// Serialize [`ResolvePersonResult`] to JSON for hosts.
pub fn resolve_person_result_to_json(result: &ResolvePersonResult) -> Option<String> {
    serde_json::to_string(result).ok()
}

pub fn storage_plan_to_json(plan: &StoragePlan) -> Option<String> {
    serde_json::to_string(plan).ok()
}
