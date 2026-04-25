use std::ffi::{c_char, CStr, CString};
use std::sync::{Mutex, OnceLock};

use crate::ingestion::{ManualEntry, ManualField};
use crate::memory::{EntryRepository, InMemoryRepository};

fn repository() -> &'static Mutex<InMemoryRepository> {
    static REPO: OnceLock<Mutex<InMemoryRepository>> = OnceLock::new();
    REPO.get_or_init(|| Mutex::new(InMemoryRepository::default()))
}

#[no_mangle]
pub extern "C" fn dreamwork_fetch_status() -> *mut c_char {
    let count = repository()
        .lock()
        .map(|repo| repo.manual_entry_count())
        .unwrap_or(0);
    CString::new(format!("Rust core bridge connected ({} entries)", count))
        .expect("status text contains no null bytes")
        .into_raw()
}

#[no_mangle]
pub extern "C" fn dreamwork_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    // SAFETY: `ptr` must be returned by `dreamwork_fetch_status` and not freed yet.
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

    let entry = ManualEntry {
        id,
        fields: vec![ManualField {
            key: "display_name".to_string(),
            value: name,
        }],
    };

    repository()
        .lock()
        .map(|mut repo| repo.save_manual_entry(entry).is_ok())
        .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn dreamwork_read_manual_entry_name(id_ptr: *const c_char) -> *mut c_char {
    if id_ptr.is_null() {
        return std::ptr::null_mut();
    }

    let id = unsafe { CStr::from_ptr(id_ptr) }
        .to_string_lossy()
        .to_string();

    let maybe_name = repository()
        .lock()
        .ok()
        .and_then(|repo| repo.get_manual_entry(&id).ok())
        .and_then(|entry| {
            entry
                .fields
                .into_iter()
                .find(|field| field.key == "display_name")
                .map(|field| field.value)
        });

    match maybe_name {
        Some(name) => CString::new(name).expect("name has no null bytes").into_raw(),
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dreamwork_manual_entry_count() -> u32 {
    repository()
        .lock()
        .map(|repo| repo.manual_entry_count() as u32)
        .unwrap_or(0)
}

