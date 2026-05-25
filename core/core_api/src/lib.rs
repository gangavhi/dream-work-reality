//! Axum HTTP surface for demos and extension bridging (ADR 0016 companion paths).

mod document_understand;
mod llm_ocr_map;

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use document_understand::{DocumentUnderstanding, LlmUnavailableError};
use dreamwork_core::{
    entity_resolution::{
        self, ExistingPerson, PersonResolution, ResolutionCandidate, ResolvePersonResult,
    },
    ingestion::{ManualEntry, ManualField},
    memory::{EntryRepository, ExtractionRepository, RepositoryBackend},
    storage_routing::{PlanStorageRequest, StoragePlan},
};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone)]
pub struct AppState {
    pub repository: Arc<Mutex<RepositoryBackend>>,
}

#[derive(Deserialize)]
pub struct SaveManualEntryRequest {
    pub id: String,
    pub display_name: String,
    #[serde(default)]
    pub fields: BTreeMap<String, String>,
}

#[derive(Serialize)]
pub struct SaveManualEntryResponse {
    pub saved: bool,
}

#[derive(Serialize, Deserialize)]
pub struct DeleteManualEntryResponse {
    pub deleted: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ManualEntryResponse {
    pub id: String,
    pub display_name: Option<String>,
    #[serde(default)]
    pub fields: BTreeMap<String, String>,
}

#[derive(Serialize)]
pub struct ProfileKeyRow {
    pub entry_id: String,
    pub profile_key: String,
}

#[derive(Deserialize)]
pub struct MapFieldsRequest {
    pub profile_name: String,
    #[serde(default)]
    pub fields: Vec<Value>,
}

#[derive(Serialize)]
pub struct MapFieldsResponse {
    pub values: serde_json::Map<String, Value>,
}

#[derive(Serialize)]
pub struct HealthResponse {
    pub status: &'static str,
}

#[derive(Serialize)]
pub struct ExtractionRunCountResponse {
    pub count: u64,
}

#[derive(Deserialize)]
pub struct ResolvePersonRequest {
    /// Stage-1 structured fields or flat key-value map (e.g. `drivers_license_number`).
    #[serde(default)]
    pub fields: BTreeMap<String, String>,
    /// When omitted, persons are loaded from the repository (`manual_entry` rows).
    #[serde(default)]
    pub existing_persons: Option<Vec<ExistingPerson>>,
}

#[derive(Serialize, Deserialize)]
pub struct ResolvePersonResponse {
    pub resolution: PersonResolution,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub person_id: Option<String>,
    pub confidence: f64,
    pub candidates: Vec<ResolutionCandidate>,
}

#[derive(Deserialize)]
pub struct UnderstandDocumentRequest {
    pub ocr_text: String,
    #[serde(default)]
    pub document_type_hint: Option<String>,
    #[serde(default)]
    pub profile_schema_keys: Option<Vec<String>>,
}

pub fn build_router(repository: Arc<Mutex<RepositoryBackend>>) -> Router {
    let state = AppState { repository };
    Router::new()
        .route("/healthz", get(healthz))
        .route("/manual-entry", post(save_manual_entry))
        .route("/manual-entry/profile-keys", get(list_profile_keys))
        .route(
            "/manual-entry/{id}",
            get(read_manual_entry).delete(delete_manual_entry),
        )
        .route("/genai/map-fields", post(map_fields))
        .route("/genai/extract-document", post(extract_document))
        .route("/ingest/understand", post(ingest_understand))
        .route("/ingest/plan-storage", post(plan_storage))
        .route("/ingest/resolve-person", post(resolve_person))
        .route("/extraction-runs/count", get(extraction_run_count))
        .with_state(state)
}

async fn healthz() -> Json<HealthResponse> {
    Json(HealthResponse { status: "ok" })
}

async fn save_manual_entry(
    State(state): State<AppState>,
    Json(payload): Json<SaveManualEntryRequest>,
) -> Json<SaveManualEntryResponse> {
    let mut fields: Vec<ManualField> = vec![ManualField {
        key: "display_name".to_string(),
        value: payload.display_name,
    }];
    for (k, v) in payload.fields {
        if k.trim().is_empty() || v.trim().is_empty() {
            continue;
        }
        fields.push(ManualField { key: k, value: v });
    }

    let entry = ManualEntry {
        id: payload.id,
        fields,
    };

    let saved = state
        .repository
        .lock()
        .map(|mut repo| repo.save_manual_entry(entry).is_ok())
        .unwrap_or(false);

    Json(SaveManualEntryResponse { saved })
}

async fn read_manual_entry(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Json<ManualEntryResponse> {
    let mut fields_map = BTreeMap::new();
    let mut display_name = None;

    if let Ok(guard) = state.repository.lock() {
        if let Ok(entry) = guard.get_manual_entry(&id) {
        for f in entry.fields {
            if f.key == "display_name" && !f.value.trim().is_empty() {
                display_name = Some(f.value.clone());
            } else if !f.key.trim().is_empty() && !f.value.trim().is_empty() {
                fields_map.insert(f.key, f.value);
            }
        }
        }
    }

    Json(ManualEntryResponse {
        id,
        display_name,
        fields: fields_map,
    })
}

async fn delete_manual_entry(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Json<DeleteManualEntryResponse> {
    let deleted = state
        .repository
        .lock()
        .map(|mut repo| repo.delete_manual_entry(&id).is_ok())
        .unwrap_or(false);
    Json(DeleteManualEntryResponse { deleted })
}

async fn list_profile_keys(State(state): State<AppState>) -> Json<Vec<ProfileKeyRow>> {
    let rows = state
        .repository
        .lock()
        .ok()
        .and_then(|repo| repo.list_manual_entries().ok())
        .map(|entries| {
            entries
                .into_iter()
                .filter_map(|entry| {
                    let profile_key = entry
                        .fields
                        .iter()
                        .find(|f| f.key == "profile_key")
                        .map(|f| f.value.clone())
                        .or_else(|| {
                            entry
                                .fields
                                .iter()
                                .find(|f| f.key == "display_name")
                                .map(|f| f.value.to_lowercase())
                        })?;
                    Some(ProfileKeyRow {
                        entry_id: entry.id,
                        profile_key,
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    Json(rows)
}

async fn map_fields(
    State(state): State<AppState>,
    Json(payload): Json<MapFieldsRequest>,
) -> Json<MapFieldsResponse> {
    let mut values = serde_json::Map::new();
    let pid = profile_id_from_name(&payload.profile_name);

    if let Ok(guard) = state.repository.lock() {
        if let Ok(entry) = guard.get_manual_entry(&pid) {
        for f in entry.fields {
            if f.key.trim().is_empty() || f.value.trim().is_empty() {
                continue;
            }
            values.insert(f.key, Value::String(f.value));
        }
        }
    }

    Json(MapFieldsResponse { values })
}

#[derive(Deserialize)]
struct ExtractDocumentRequest {
    document_type: String,
    raw_text: String,
}

#[derive(Serialize)]
struct ExtractDocumentResponse {
    values: BTreeMap<String, String>,
}

async fn extract_document(
    headers: axum::http::HeaderMap,
    Json(payload): Json<ExtractDocumentRequest>,
) -> Result<Json<ExtractDocumentResponse>, (StatusCode, Json<LlmUnavailableError>)> {
    let api_key = document_understand::api_key_from_env_or_header(
        headers
            .get("X-Dreamwork-Openai-Api-Key")
            .and_then(|v| v.to_str().ok()),
    )
    .ok_or_else(|| {
        (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(LlmUnavailableError {
                error: "llm_unavailable".into(),
                message: "Set DREAMWORK_OPENAI_API_KEY or OPENAI_API_KEY for GenAI field extraction."
                    .into(),
            }),
        )
    })?;

    let hint = if payload.document_type.is_empty() {
        "driver_license"
    } else {
        payload.document_type.as_str()
    };

    match llm_ocr_map::map_ocr_to_string_map(
        &api_key,
        &document_understand::openai_base_url(),
        &document_understand::openai_model(),
        &payload.raw_text,
        Some(hint),
        true,
    )
    .await
    {
        Ok(values) => {
            let normalized = values
                .into_iter()
                .map(|(k, v)| (dreamwork_core::profile_keys::normalize_field_key(&k), v))
                .collect();
            Ok(Json(ExtractDocumentResponse {
                values: normalized,
            }))
        }
        Err(e) => Err((
            StatusCode::BAD_GATEWAY,
            Json(LlmUnavailableError {
                error: "llm_error".into(),
                message: e,
            }),
        )),
    }
}

async fn ingest_understand(
    Json(payload): Json<UnderstandDocumentRequest>,
) -> Result<Json<DocumentUnderstanding>, (StatusCode, Json<LlmUnavailableError>)> {
    if payload.ocr_text.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(LlmUnavailableError {
                error: "invalid_request".into(),
                message: "ocr_text must not be empty".into(),
            }),
        ));
    }

    let hint = payload.document_type_hint.as_deref();
    let keys = payload.profile_schema_keys.as_deref();

    match document_understand::understand_document_from_env(
        &payload.ocr_text,
        hint,
        keys,
    )
    .await
    {
        Ok(doc) => Ok(Json(doc)),
        Err(e) if e.error == "llm_unavailable" => Err((StatusCode::SERVICE_UNAVAILABLE, Json(e))),
        Err(e) => Err((StatusCode::BAD_GATEWAY, Json(e))),
    }
}

#[derive(Deserialize)]
struct PlanStorageHttpRequest {
    #[serde(default)]
    fields: BTreeMap<String, String>,
    #[serde(default)]
    person_id: Option<String>,
    #[serde(default)]
    profile_schema_keys: Option<Vec<String>>,
}

async fn plan_storage(Json(payload): Json<PlanStorageHttpRequest>) -> Json<StoragePlan> {
    Json(dreamwork_core::storage_routing::plan_storage(&PlanStorageRequest {
        fields: payload.fields,
        person_id: payload.person_id,
        profile_schema_keys: payload.profile_schema_keys,
        model_path: None,
        document_type: None,
        sqlite_schema: dreamwork_core::runtime::peek_sqlite_schema_snapshot(),
    }))
}

async fn resolve_person(
    State(state): State<AppState>,
    Json(payload): Json<ResolvePersonRequest>,
) -> Json<ResolvePersonResponse> {
    let existing = if let Some(persons) = payload.existing_persons {
        persons
    } else {
        state
            .repository
            .lock()
            .ok()
            .and_then(|repo| repo.list_manual_entries().ok())
            .map(|entries| {
                entries
                    .into_iter()
                    .map(|entry| {
                        let person_id = entry.id.clone();
                        ExistingPerson {
                            person_id,
                            fields: entity_resolution::manual_entry_to_fields(&entry),
                        }
                    })
                    .collect()
            })
            .unwrap_or_default()
    };

    let result: ResolvePersonResult =
        entity_resolution::resolve_person(&payload.fields, &existing);

    Json(ResolvePersonResponse {
        resolution: result.resolution,
        person_id: result.person_id,
        confidence: result.confidence,
        candidates: result.candidates,
    })
}

async fn extraction_run_count(State(state): State<AppState>) -> Json<ExtractionRunCountResponse> {
    let count = state
        .repository
        .lock()
        .map(|repo| repo.extraction_run_count() as u64)
        .unwrap_or(0);
    Json(ExtractionRunCountResponse { count })
}

fn profile_id_from_name(name: &str) -> String {
    let n = name
        .trim()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase();
    if n.is_empty() {
        return "profile-unknown".to_string();
    }
    let slug = n
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|p| !p.is_empty())
        .collect::<Vec<_>>()
        .join("-");
    format!("profile-{slug}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{body::Body, http::Request};
    use serde_json::json;
    use tower::ServiceExt;

    fn sample_repo() -> Arc<Mutex<RepositoryBackend>> {
        Arc::new(Mutex::new(RepositoryBackend::memory_only()))
    }

    #[tokio::test]
    async fn healthz_returns_ok() {
        let app = build_router(sample_repo());
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/healthz")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), axum::http::StatusCode::OK);
    }

    #[tokio::test]
    async fn manual_entry_round_trip_json() {
        let app = build_router(sample_repo());
        let save = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/manual-entry")
                    .header(axum::http::header::CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        json!({"id":"api-1","display_name":"River"}).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(save.status(), axum::http::StatusCode::OK);

        let read = app
            .oneshot(
                Request::builder()
                    .uri("/manual-entry/api-1")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(read.status(), axum::http::StatusCode::OK);
        let body = axum::body::to_bytes(read.into_body(), usize::MAX)
            .await
            .unwrap();
        let parsed: ManualEntryResponse = serde_json::from_slice(&body).unwrap();
        assert_eq!(parsed.id, "api-1");
        assert_eq!(parsed.display_name.as_deref(), Some("River"));
    }

    #[tokio::test]
    async fn manual_entry_delete_returns_deleted_true() {
        let app = build_router(sample_repo());
        let save = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/manual-entry")
                    .header(axum::http::header::CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        json!({"id":"api-del-1","display_name":"Temp"}).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(save.status(), axum::http::StatusCode::OK);

        let del = app
            .oneshot(
                Request::builder()
                    .method("DELETE")
                    .uri("/manual-entry/api-del-1")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(del.status(), axum::http::StatusCode::OK);
        let body = axum::body::to_bytes(del.into_body(), usize::MAX)
            .await
            .unwrap();
        let parsed: DeleteManualEntryResponse = serde_json::from_slice(&body).unwrap();
        assert!(parsed.deleted);
    }

    #[tokio::test]
    async fn plan_storage_endpoint_routes_canonical_and_extension() {
        let app = build_router(sample_repo());
        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/ingest/plan-storage")
                    .header(axum::http::header::CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        json!({
                            "fields": { "email": "a@b.com", "barcode_payload": "xyz" },
                            "person_id": "p1"
                        })
                        .to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), axum::http::StatusCode::OK);
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let plan: StoragePlan = serde_json::from_slice(&body).unwrap();
        assert_eq!(plan.summary.canonical_count, 1);
        assert_eq!(plan.summary.extension_count, 1);
    }

    #[tokio::test]
    async fn resolve_person_endpoint_matches_by_drivers_license() {
        let repo = sample_repo();
        let app = build_router(repo.clone());
        let save = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/manual-entry")
                    .header(axum::http::header::CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        json!({
                            "id": "stored-1",
                            "display_name": "Casey",
                            "fields": { "drivers_license_number": "DL999" }
                        })
                        .to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(save.status(), axum::http::StatusCode::OK);

        let resolve = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/ingest/resolve-person")
                    .header(axum::http::header::CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        json!({ "fields": { "drivers_license_number": "DL999" } }).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resolve.status(), axum::http::StatusCode::OK);
        let body = axum::body::to_bytes(resolve.into_body(), usize::MAX)
            .await
            .unwrap();
        let parsed: ResolvePersonResponse = serde_json::from_slice(&body).unwrap();
        assert_eq!(parsed.resolution, PersonResolution::MatchExisting);
        assert_eq!(parsed.person_id.as_deref(), Some("stored-1"));
        assert!(parsed.confidence >= 0.72);
    }

    #[tokio::test]
    async fn sqlite_repo_works_behind_router() {
        let backend = RepositoryBackend::new_in_memory_sqlite().expect("sqlite opens");
        let app = build_router(Arc::new(Mutex::new(backend)));
        let save = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/manual-entry")
                    .header(axum::http::header::CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        json!({"id":"sql-1","display_name":"Lake"}).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(save.status(), axum::http::StatusCode::OK);
    }

    #[tokio::test]
    async fn ingest_understand_rejects_empty_ocr_text() {
        let app = build_router(sample_repo());
        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/ingest/understand")
                    .header(axum::http::header::CONTENT_TYPE, "application/json")
                    .body(Body::from(json!({"ocr_text": "  "}).to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn ingest_understand_without_api_key_returns_503() {
        let _guard = ApiKeyGuard::clear();
        let app = build_router(sample_repo());
        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/ingest/understand")
                    .header(axum::http::header::CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        json!({"ocr_text": "CALIFORNIA DRIVER LICENSE"}).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let parsed: LlmUnavailableError = serde_json::from_slice(&body).unwrap();
        assert_eq!(parsed.error, "llm_unavailable");
        assert!(parsed.message.contains("DREAMWORK_OPENAI_API_KEY"));
    }

    /// Clears API key env vars for the test and restores prior values on drop.
    struct ApiKeyGuard {
        dreamwork: Option<String>,
        openai: Option<String>,
    }

    impl ApiKeyGuard {
        fn clear() -> Self {
            let dreamwork = std::env::var("DREAMWORK_OPENAI_API_KEY").ok();
            let openai = std::env::var("OPENAI_API_KEY").ok();
            std::env::remove_var("DREAMWORK_OPENAI_API_KEY");
            std::env::remove_var("OPENAI_API_KEY");
            Self { dreamwork, openai }
        }
    }

    impl Drop for ApiKeyGuard {
        fn drop(&mut self) {
            match &self.dreamwork {
                Some(v) => std::env::set_var("DREAMWORK_OPENAI_API_KEY", v),
                None => std::env::remove_var("DREAMWORK_OPENAI_API_KEY"),
            }
            match &self.openai {
                Some(v) => std::env::set_var("OPENAI_API_KEY", v),
                None => std::env::remove_var("OPENAI_API_KEY"),
            }
        }
    }
}
