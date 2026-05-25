//! C ABI for Swift/Kotlin hosts (ADR 0013). **Must not panic** across the boundary.
//!
//! Returned strings are heap-owned and released with [`dreamwork_string_free`].
#![allow(clippy::not_unsafe_ptr_arg_deref)] // C ABI entrypoints intentionally consume caller-controlled pointers.

use std::ffi::{c_char, CStr, CString};
use std::path::PathBuf;

use crate::ocr::NormalizedDocument;
use crate::runtime;

fn leaked_static_error_message() -> *mut c_char {
    static MSG: &[u8] = b"Rust core: allocation failed\0";
    CString::from_vec_with_nul(MSG.to_vec())
        .expect("static message")
        .into_raw()
}

#[no_mangle]
pub extern "C" fn dreamwork_fetch_status() -> *mut c_char {
    let count = runtime::manual_entry_count_u32();
    match CString::new(format!("Rust core bridge connected ({count} entries)")) {
        Ok(s) => s.into_raw(),
        Err(_) => leaked_static_error_message(),
    }
}

#[no_mangle]
pub extern "C" fn dreamwork_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

#[no_mangle]
pub extern "C" fn dreamwork_save_manual_entry(
    id_ptr: *const c_char,
    name_ptr: *const c_char,
) -> bool {
    if id_ptr.is_null() || name_ptr.is_null() {
        return false;
    }

    let id = unsafe { CStr::from_ptr(id_ptr) }
        .to_string_lossy()
        .to_string();
    let name = unsafe { CStr::from_ptr(name_ptr) }
        .to_string_lossy()
        .to_string();

    runtime::save_manual_display_name(id, name)
}

#[no_mangle]
pub extern "C" fn dreamwork_save_manual_entry_json(ptr: *const c_char) -> bool {
    if ptr.is_null() {
        return false;
    }
    let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy();
    runtime::save_manual_entry_json(&s)
}

#[no_mangle]
pub extern "C" fn dreamwork_delete_manual_entry(id_ptr: *const c_char) -> bool {
    if id_ptr.is_null() {
        return false;
    }
    let id = unsafe { CStr::from_ptr(id_ptr) }
        .to_string_lossy()
        .to_string();
    runtime::delete_manual_entry(&id)
}

#[no_mangle]
pub extern "C" fn dreamwork_read_manual_entry_name(id_ptr: *const c_char) -> *mut c_char {
    if id_ptr.is_null() {
        return std::ptr::null_mut();
    }

    let id = unsafe { CStr::from_ptr(id_ptr) }
        .to_string_lossy()
        .to_string();

    match runtime::read_manual_display_name(&id) {
        Some(name) => match CString::new(name) {
            Ok(c) => c.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dreamwork_manual_entry_count() -> u32 {
    runtime::manual_entry_count_u32()
}

/// Heap-owned JSON array of manual entries (or null). Free with [`dreamwork_string_free`].
#[no_mangle]
pub extern "C" fn dreamwork_manual_entries_json() -> *mut c_char {
    match runtime::manual_entries_json() {
        Some(j) => match CString::new(j) {
            Ok(c) => c.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        None => std::ptr::null_mut(),
    }
}

/// Points SQLite persistence at `path` (UTF-8, NUL-terminated file path). Call once before other APIs for durable storage.
#[no_mangle]
pub extern "C" fn dreamwork_repository_configure_persistent_sqlite(path: *const c_char) -> bool {
    if path.is_null() {
        return false;
    }
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };
    runtime::try_configure_persistent_sqlite(PathBuf::from(path_str))
}

#[no_mangle]
pub extern "C" fn dreamwork_extraction_run_count() -> u32 {
    runtime::extraction_run_count_u32()
}

/// Accepts JSON matching [`NormalizedDocument`] from Apple Vision / ML Kit adapters.
#[no_mangle]
pub extern "C" fn dreamwork_ocr_apply_normalized_json(ptr: *const c_char) -> bool {
    if ptr.is_null() {
        return false;
    }
    let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy();
    match serde_json::from_str::<NormalizedDocument>(&s) {
        Ok(doc) => {
            runtime::ingest_normalized_document(doc);
            true
        }
        Err(_) => false,
    }
}

/// Stage 3: rules-only person resolution. Request JSON: `{ "fields": {...}, "existing_persons"?: [...] }`.
/// When `existing_persons` is omitted, loads from the configured repository. Returns result JSON or null.
#[no_mangle]
pub extern "C" fn dreamwork_resolve_person_json(ptr: *const c_char) -> *mut c_char {
    if ptr.is_null() {
        return std::ptr::null_mut();
    }
    let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy();
    match crate::ingest::resolve_person_from_json(&s) {
        Ok(result) => match crate::ingest::resolve_person_result_to_json(&result) {
            Some(j) => match CString::new(j) {
                Ok(c) => c.into_raw(),
                Err(_) => std::ptr::null_mut(),
            },
            None => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// Local ML document classification. Request JSON: `{ "layout_text", "model_path"? }`.
#[no_mangle]
pub extern "C" fn dreamwork_classify_document_json(ptr: *const c_char) -> *mut c_char {
    if ptr.is_null() {
        return std::ptr::null_mut();
    }
    let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy();
    match crate::ml_document_classifier::classify_document_from_json(&s) {
        Ok(result) => match serde_json::to_string(&result) {
            Ok(j) => match CString::new(j) {
                Ok(c) => c.into_raw(),
                Err(_) => std::ptr::null_mut(),
            },
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// Stage 2: local ML storage routing plan. Request JSON: `{ "fields": {...}, "person_id"?: "...", "model_path"?: "...", ... }`.
#[no_mangle]
pub extern "C" fn dreamwork_plan_storage_json(ptr: *const c_char) -> *mut c_char {
    if ptr.is_null() {
        return std::ptr::null_mut();
    }
    let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy();
    match crate::ingest::plan_storage_from_json(&s) {
        Ok(plan) => match crate::ingest::storage_plan_to_json(&plan) {
            Some(j) => match CString::new(j) {
                Ok(c) => c.into_raw(),
                Err(_) => std::ptr::null_mut(),
            },
            None => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// On-device field mapping from layout OCR text (zero egress). Request JSON: `{ "layout_text", "profile_schema_keys"?, "model_path"? }`.
#[no_mangle]
pub extern "C" fn dreamwork_map_document_fields_json(ptr: *const c_char) -> *mut c_char {
    if ptr.is_null() {
        return std::ptr::null_mut();
    }
    let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy();
    match crate::local_document_mapper::map_document_fields_from_json(&s) {
        Ok(result) => match serde_json::to_string(&result) {
            Ok(j) => match CString::new(j) {
                Ok(c) => c.into_raw(),
                Err(_) => std::ptr::null_mut(),
            },
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// Returns heap-owned JSON for the last OCR payload (or null). Free with [`dreamwork_string_free`].
#[no_mangle]
pub extern "C" fn dreamwork_ocr_last_document_json() -> *mut c_char {
    match runtime::peek_last_normalized_document_json() {
        Some(j) => match CString::new(j) {
            Ok(c) => c.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        None => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn ffi_round_trip_manual_entry() {
        let id = CString::new("ffi-person-round-trip").unwrap();
        let name = CString::new("Jordan").unwrap();
        assert!(dreamwork_save_manual_entry(id.as_ptr(), name.as_ptr()));
        let read = dreamwork_read_manual_entry_name(id.as_ptr());
        assert!(!read.is_null());
        let s = unsafe { CStr::from_ptr(read) }
            .to_string_lossy()
            .into_owned();
        assert_eq!(s, "Jordan");
        dreamwork_string_free(read);
    }

    #[test]
    fn ffi_manual_entry_json_round_trip() {
        let json = CString::new(
            r#"{"id":"json-person","fields":[{"key":"display_name","value":"Taylor"},{"key":"email","value":"t@example.com"}]}"#,
        )
        .unwrap();
        assert!(dreamwork_save_manual_entry_json(json.as_ptr()));
        let out = dreamwork_manual_entries_json();
        assert!(!out.is_null());
        let s = unsafe { CStr::from_ptr(out) }.to_string_lossy();
        assert!(s.contains("json-person"));
        assert!(s.contains("t@example.com"));
        dreamwork_string_free(out);
    }

    #[test]
    fn ffi_resolve_person_json() {
        let json = CString::new(
            r#"{"id":"ffi-resolve-person","fields":[{"key":"display_name","value":"Casey"},{"key":"drivers_license_number","value":"DL-FFI-1"}]}"#,
        )
        .unwrap();
        assert!(dreamwork_save_manual_entry_json(json.as_ptr()));

        let req = CString::new(r#"{"fields":{"drivers_license_number":"DL-FFI-1"}}"#).unwrap();
        let out = dreamwork_resolve_person_json(req.as_ptr());
        assert!(!out.is_null());
        let s = unsafe { CStr::from_ptr(out) }.to_string_lossy();
        assert!(s.contains("match_existing"));
        dreamwork_string_free(out);
    }

    #[test]
    fn ffi_plan_storage_json() {
        let req = CString::new(r#"{"fields":{"email":"a@b.com","barcode":"x"}}"#).unwrap();
        let out = dreamwork_plan_storage_json(req.as_ptr());
        assert!(!out.is_null());
        let s = unsafe { CStr::from_ptr(out) }.to_string_lossy();
        assert!(s.contains("storage_planner_model_missing"));
        assert!(s.contains(r#""operations":[]"#));
        dreamwork_string_free(out);
    }

    #[test]
    fn ffi_ocr_json_round_trip() {
        let before = dreamwork_extraction_run_count();
        let json = CString::new(r#"{"pages":[{"blocks":[{"text":"Hi","confidence":1.0,"bounds":{"x":0,"y":0,"width":1,"height":0.1}}]}]}"#).unwrap();
        assert!(dreamwork_ocr_apply_normalized_json(json.as_ptr()));
        assert!(dreamwork_extraction_run_count() > before);
        let out = dreamwork_ocr_last_document_json();
        assert!(!out.is_null());
        dreamwork_string_free(out);
    }
}
