//! Axum HTTP surface for demos and extension bridging (ADR 0016 companion paths).

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

#[derive(Clone)]
pub struct AppState {
    pub repository: Arc<Mutex<RepositoryBackend>>,
}

#[derive(Deserialize)]
pub struct SaveManualEntryRequest {
    pub id: String,
    pub display_name: String,
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
        .route(
            "/manual-entry/{id}",
            get(read_manual_entry).delete(delete_manual_entry),
        )
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
    let entry = ManualEntry {
        id: payload.id,
        fields: vec![ManualField {
            key: "display_name".to_string(),
            value: payload.display_name,
        }],
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
    let display_name = state
        .repository
        .lock()
        .ok()
        .and_then(|repo| repo.get_manual_entry(&id).ok())
        .and_then(|entry| {
            entry
                .fields
                .into_iter()
                .find(|f| f.key == "display_name")
                .map(|f| f.value)
        });

    Json(ManualEntryResponse { id, display_name })
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

async fn extraction_run_count(State(state): State<AppState>) -> Json<ExtractionRunCountResponse> {
    let count = state
        .repository
        .lock()
        .map(|repo| repo.extraction_run_count() as u64)
        .unwrap_or(0);
    Json(ExtractionRunCountResponse { count })
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
