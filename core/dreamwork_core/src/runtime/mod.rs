//! Shared process-local state backing C ABI and UniFFI exports (ADR 0013).
//!
//! Single-thread assumptions match mobile UI drives; still guarded with [`Mutex`].

use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use crate::extraction::{default_import_meta, ExtractionRunRecord};
use crate::ingestion::{ManualEntry, ManualField};
use crate::memory::{EntryRepository, ExtractionRepository, RepositoryBackend};
use crate::ocr::{ExtractionRunMeta, NormalizedDocument};

static PERSISTENT_DB_PATH: Mutex<Option<PathBuf>> = Mutex::new(None);

fn open_repository_backend() -> RepositoryBackend {
    if let Ok(guard) = PERSISTENT_DB_PATH.lock() {
        if let Some(ref path) = *guard {
            if let Ok(repo) = RepositoryBackend::open_sqlite_file(path) {
                return repo;
            }
        }
    }
    RepositoryBackend::new_in_memory_sqlite().unwrap_or_else(|_| RepositoryBackend::memory_only())
}

/// Configure on-disk SQLite **before** the repository is opened for the first process-wide init (typically once at app launch).
///
/// Call this from the host app before any other `dreamwork_*` APIs if data must survive restarts.
/// Returns `false` if a path was already configured or the path is unusable.
pub fn try_configure_persistent_sqlite(path: PathBuf) -> bool {
    if path.as_os_str().is_empty() {
        return false;
    }
    let mut guard = match PERSISTENT_DB_PATH.lock() {
        Ok(g) => g,
        Err(_) => return false,
    };
    if guard.is_some() {
        return false;
    }
    *guard = Some(path);
    true
}

pub(crate) fn repository() -> &'static Mutex<RepositoryBackend> {
    static REPO: OnceLock<Mutex<RepositoryBackend>> = OnceLock::new();
    REPO.get_or_init(|| Mutex::new(open_repository_backend()))
}

static LAST_OCR: OnceLock<Mutex<Option<NormalizedDocument>>> = OnceLock::new();

fn last_ocr_slot() -> &'static Mutex<Option<NormalizedDocument>> {
    LAST_OCR.get_or_init(|| Mutex::new(None))
}

/// UniFFI / tools entrypoint mirroring [`crate::ffi::dreamwork_manual_entry_count`].
pub fn manual_entry_count_u32() -> u32 {
    repository()
        .lock()
        .map(|r| r.manual_entry_count() as u32)
        .unwrap_or(0)
}

/// JSON array of [`ManualEntry`](crate::ingestion::ManualEntry) for UI hosts.
pub fn manual_entries_json() -> Option<String> {
    let entries = repository()
        .lock()
        .ok()
        .and_then(|r| r.list_manual_entries().ok())?;
    serde_json::to_string(&entries).ok()
}

pub fn save_manual_display_name(id: String, display_name: String) -> bool {
    let entry = ManualEntry {
        id,
        fields: vec![ManualField {
            key: "display_name".to_string(),
            value: display_name,
        }],
    };
    repository()
        .lock()
        .map(|mut r| r.save_manual_entry(entry).is_ok())
        .unwrap_or(false)
}

pub fn read_manual_display_name(id: &str) -> Option<String> {
    repository()
        .lock()
        .ok()
        .and_then(|repo| repo.get_manual_entry(id).ok())
        .and_then(|entry| {
            entry
                .fields
                .into_iter()
                .find(|f| f.key == "display_name")
                .map(|f| f.value)
        })
}

/// Stores the last OCR payload and appends an extraction run row (ADR 0004).
pub fn ingest_normalized_document(doc: NormalizedDocument) {
    ingest_normalized_document_with_meta(doc, default_import_meta());
}

/// Same as [`ingest_normalized_document`] but records explicit engine provenance.
pub fn ingest_normalized_document_with_meta(doc: NormalizedDocument, meta: ExtractionRunMeta) {
    let _ = last_ocr_slot()
        .lock()
        .map(|mut slot| *slot = Some(doc.clone()));
    let record = ExtractionRunRecord::new(doc, meta);
    let _ = repository()
        .lock()
        .map(|mut r| r.save_extraction_run(&record));
}

pub fn extraction_run_count_u32() -> u32 {
    repository()
        .lock()
        .map(|r| r.extraction_run_count() as u32)
        .unwrap_or(0)
}

pub fn take_last_normalized_document() -> Option<NormalizedDocument> {
    last_ocr_slot().lock().ok().and_then(|mut g| g.take())
}

pub fn peek_last_normalized_document_json() -> Option<String> {
    last_ocr_slot()
        .lock()
        .ok()
        .and_then(|g| g.as_ref().and_then(|doc| serde_json::to_string(doc).ok()))
}
