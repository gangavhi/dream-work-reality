use std::sync::{Arc, Mutex};

use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use dreamwork_core::{
    ingestion::{ManualEntry, ManualField},
    memory::{EntryRepository, InMemoryRepository},
};
use serde::{Deserialize, Serialize};

#[derive(Clone)]
struct AppState {
    repository: Arc<Mutex<InMemoryRepository>>,
}

#[derive(Deserialize)]
struct SaveManualEntryRequest {
    id: String,
    display_name: String,
}

#[derive(Serialize)]
struct SaveManualEntryResponse {
    saved: bool,
}

#[derive(Serialize)]
struct ManualEntryResponse {
    id: String,
    display_name: Option<String>,
}

#[derive(Serialize)]
struct HealthResponse {
    status: &'static str,
}

#[tokio::main]
async fn main() {
    let state = AppState {
        repository: Arc::new(Mutex::new(InMemoryRepository::default())),
    };

    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/manual-entry", post(save_manual_entry))
        .route("/manual-entry/{id}", get(read_manual_entry))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080")
        .await
        .expect("binds to port 8080");
    axum::serve(listener, app)
        .await
        .expect("server should stay alive");
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
