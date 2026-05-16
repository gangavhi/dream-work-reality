//! Stage 2 rules-only storage routing: map extracted fields to `manual_field` vs extension keys.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::profile_keys::{is_canonical_profile_key, normalize_field_key};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StorageOperationKind {
    /// Known profile slot → `manual_field` on the person row.
    UpsertManualField,
    /// Unknown / document-specific key → still `manual_field`, flagged for review.
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
    /// When set, only these keys count as canonical (otherwise [`crate::profile_keys::canonical_profile_keys`]).
    #[serde(default)]
    pub profile_schema_keys: Option<Vec<String>>,
}

/// Build a storage plan without executing writes (ADR 0005 executor comes later).
pub fn plan_storage(req: &PlanStorageRequest) -> StoragePlan {
    let canonical_set: std::collections::BTreeSet<String> = req
        .profile_schema_keys
        .as_ref()
        .map(|keys| {
            keys.iter()
                .map(|k| normalize_field_key(k))
                .filter(|k| !k.is_empty())
                .collect()
        })
        .unwrap_or_else(|| {
            crate::profile_keys::canonical_profile_keys()
                .iter()
                .map(|s| (*s).to_string())
                .collect()
        });

    let person_id = req
        .person_id
        .as_ref()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(str::to_string);

    let mut canonical_count = 0_u32;
    let mut extension_count = 0_u32;
    let mut skipped_empty = 0_u32;
    let mut operations = Vec::new();

    for (raw_key, raw_value) in &req.fields {
        let value = raw_value.trim();
        if value.is_empty() {
            skipped_empty += 1;
            continue;
        }
        let key = normalize_field_key(raw_key);
        if key.is_empty() {
            skipped_empty += 1;
            continue;
        }

        let is_canonical = canonical_set.contains(&key) || is_canonical_profile_key(&key);
        let (op, reason) = if is_canonical {
            canonical_count += 1;
            (
                StorageOperationKind::UpsertManualField,
                "canonical_profile_key".to_string(),
            )
        } else {
            extension_count += 1;
            (
                StorageOperationKind::UpsertExtensionField,
                "extension_field".to_string(),
            )
        };

        operations.push(StorageOperation {
            op,
            person_id: person_id.clone(),
            key,
            value: value.to_string(),
            reason,
        });
    }

    operations.sort_by(|a, b| a.key.cmp(&b.key));

    StoragePlan {
        operations,
        summary: StoragePlanSummary {
            canonical_count,
            extension_count,
            skipped_empty,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn routes_canonical_to_manual_field() {
        let mut fields = BTreeMap::new();
        fields.insert("first_name".into(), "Alex".into());
        fields.insert("dl_number".into(), "D123".into());
        let plan = plan_storage(&PlanStorageRequest {
            fields,
            person_id: Some("p1".into()),
            profile_schema_keys: None,
        });
        assert_eq!(plan.summary.canonical_count, 2);
        assert_eq!(plan.summary.extension_count, 0);
        assert!(plan.operations.iter().all(|o| {
            o.op == StorageOperationKind::UpsertManualField && o.person_id.as_deref() == Some("p1")
        }));
        assert!(
            plan.operations
                .iter()
                .any(|o| o.key == "legal_first_name")
        );
        assert!(
            plan.operations
                .iter()
                .any(|o| o.key == "drivers_license_number")
        );
    }

    #[test]
    fn routes_unknown_to_extension() {
        let mut fields = BTreeMap::new();
        fields.insert("barcode_payload".into(), "xyz".into());
        let plan = plan_storage(&PlanStorageRequest {
            fields,
            person_id: None,
            profile_schema_keys: None,
        });
        assert_eq!(plan.summary.extension_count, 1);
        assert_eq!(plan.operations[0].op, StorageOperationKind::UpsertExtensionField);
    }

    #[test]
    fn skips_empty_values() {
        let mut fields = BTreeMap::new();
        fields.insert("email".into(), "  ".into());
        let plan = plan_storage(&PlanStorageRequest {
            fields,
            person_id: None,
            profile_schema_keys: None,
        });
        assert!(plan.operations.is_empty());
        assert_eq!(plan.summary.skipped_empty, 1);
    }
}
