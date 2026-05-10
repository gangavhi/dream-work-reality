//! UniFFI bindings for Kotlin/Swift hosts (ADR 0013 optional path alongside raw C ABI).

uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn dw_manual_entry_count() -> u32 {
    dreamwork_core::runtime::manual_entry_count_u32()
}

#[uniffi::export]
pub fn dw_extraction_run_count() -> u32 {
    dreamwork_core::runtime::extraction_run_count_u32()
}

#[uniffi::export]
pub fn dw_save_manual_display_name(id: String, display_name: String) -> bool {
    dreamwork_core::runtime::save_manual_display_name(id, display_name)
}

#[uniffi::export]
pub fn dw_read_manual_display_name(id: String) -> Option<String> {
    dreamwork_core::runtime::read_manual_display_name(&id)
}

#[uniffi::export]
pub fn dw_ocr_apply_normalized_json(json: String) -> bool {
    match serde_json::from_str::<dreamwork_core::ocr::NormalizedDocument>(&json) {
        Ok(doc) => {
            dreamwork_core::runtime::ingest_normalized_document(doc);
            true
        }
        Err(_) => false,
    }
}

#[uniffi::export]
pub fn dw_ocr_last_document_json() -> Option<String> {
    dreamwork_core::runtime::peek_last_normalized_document_json()
}
