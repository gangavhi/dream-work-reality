use std::sync::{Arc, Mutex};

use dreamwork_core::memory::RepositoryBackend;

#[tokio::main]
async fn main() {
    let repository = Arc::new(Mutex::new(
        RepositoryBackend::new_in_memory_sqlite()
            .unwrap_or_else(|_| RepositoryBackend::memory_only()),
    ));

    let app = core_api::build_router(repository);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080")
        .await
        .expect("binds to port 8080");

    axum::serve(listener, app)
        .await
        .expect("server should stay alive");
}
