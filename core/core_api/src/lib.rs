//! Axum HTTP surface for demos and extension bridging (ADR 0016 companion paths).

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use dreamwork_core::{
    ingestion::{ManualEntry, ManualField},
    memory::{EntryRepository, ExtractionRepository, RepositoryBackend},
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
}
