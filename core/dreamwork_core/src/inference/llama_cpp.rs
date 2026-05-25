#[cfg(target_os = "ios")]
use std::ffi::{c_char, c_int, c_uint, c_ulong, CStr, CString};

use super::InferenceError;

#[cfg(target_os = "ios")]
extern "C" {
    fn dreamwork_llama_generate_json(
        model_path: *const c_char,
        user_prompt: *const c_char,
        max_tokens: c_uint,
        out: *mut c_char,
        out_len: c_ulong,
        err: *mut c_char,
        err_len: c_ulong,
    ) -> c_int;
}

pub fn generate_constrained_json(
    model_path: &str,
    user_prompt: &str,
    max_tokens: u32,
) -> Result<String, InferenceError> {
    platform_generate_constrained_json(model_path, user_prompt, max_tokens)
}

#[cfg(target_os = "ios")]
fn platform_generate_constrained_json(
    model_path: &str,
    user_prompt: &str,
    max_tokens: u32,
) -> Result<String, InferenceError> {
    let model_path = CString::new(model_path)
        .map_err(|_| InferenceError::Session("model path contains a NUL byte".to_string()))?;
    let user_prompt = CString::new(user_prompt)
        .map_err(|_| InferenceError::Session("prompt contains a NUL byte".to_string()))?;

    let mut out = vec![0i8; 128 * 1024];
    let mut err = vec![0i8; 2048];
    let code = unsafe {
        dreamwork_llama_generate_json(
            model_path.as_ptr(),
            user_prompt.as_ptr(),
            max_tokens,
            out.as_mut_ptr(),
            out.len() as c_ulong,
            err.as_mut_ptr(),
            err.len() as c_ulong,
        )
    };

    if code == 0 {
        let text = unsafe { CStr::from_ptr(out.as_ptr()) }
            .to_string_lossy()
            .trim()
            .to_string();
        if text.is_empty() {
            return Err(InferenceError::Session(
                "llama.cpp returned an empty JSON response".to_string(),
            ));
        }
        return Ok(text);
    }

    let message = unsafe { CStr::from_ptr(err.as_ptr()) }
        .to_string_lossy()
        .trim()
        .to_string();
    Err(InferenceError::Session(format!(
        "llama.cpp generation failed with code {code}: {}",
        if message.is_empty() {
            "no detail".to_string()
        } else {
            message
        }
    )))
}

#[cfg(not(target_os = "ios"))]
fn platform_generate_constrained_json(
    _model_path: &str,
    _user_prompt: &str,
    _max_tokens: u32,
) -> Result<String, InferenceError> {
    Err(InferenceError::Unsupported(
        "llama.cpp generation is only linked in the iOS app target".to_string(),
    ))
}
