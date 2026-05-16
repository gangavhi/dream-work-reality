//! Stage 1: structured document understanding via OpenAI-compatible chat API (dev).

use serde::{Deserialize, Serialize};
use serde_json::Value;

use dreamwork_core::profile_keys::{canonical_profile_keys, normalize_field_key};

use crate::llm_ocr_map;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnderstandField {
    pub key: String,
    pub value: String,
    pub confidence: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocumentUnderstanding {
    pub document_type: String,
    pub document_type_confidence: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub issuer_region: Option<String>,
    #[serde(default)]
    pub fields: Vec<UnderstandField>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub display_name_hint: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmUnavailableError {
    pub error: String,
    pub message: String,
}

pub fn api_key_from_env_or_header(header_key: Option<&str>) -> Option<String> {
    if let Some(k) = header_key {
        let t = k.trim();
        if !t.is_empty() {
            return Some(t.to_string());
        }
    }
    for name in ["DREAMWORK_OPENAI_API_KEY", "OPENAI_API_KEY"] {
        if let Ok(v) = std::env::var(name) {
            let t = v.trim();
            if !t.is_empty() {
                return Some(t.to_string());
            }
        }
    }
    None
}

pub fn openai_base_url() -> String {
    std::env::var("DREAMWORK_OPENAI_BASE_URL")
        .or_else(|_| std::env::var("OPENAI_BASE_URL"))
        .unwrap_or_else(|_| "https://api.openai.com/v1".to_string())
}

pub fn openai_model() -> String {
    std::env::var("DREAMWORK_OPENAI_MODEL")
        .or_else(|_| std::env::var("OPENAI_MODEL"))
        .unwrap_or_else(|_| "gpt-4o-mini".to_string())
}

/// Dev entrypoint: reads API key from env (and optional header override).
pub async fn understand_document_from_env(
    ocr_text: &str,
    document_type_hint: Option<&str>,
    profile_schema_keys: Option<&[String]>,
) -> Result<DocumentUnderstanding, LlmUnavailableError> {
    let api_key = api_key_from_env_or_header(None).ok_or_else(|| LlmUnavailableError {
        error: "llm_unavailable".into(),
        message: "No API key configured. Set DREAMWORK_OPENAI_API_KEY or OPENAI_API_KEY for cloud document understanding, or continue with on-device OCR and local parsing.".into(),
    })?;
    understand_document(
        &api_key,
        ocr_text,
        document_type_hint,
        profile_schema_keys,
    )
    .await
    .map_err(|e| LlmUnavailableError {
        error: "llm_error".into(),
        message: e.to_string(),
    })
}

pub async fn understand_document(
    api_key: &str,
    ocr_text: &str,
    document_type_hint: Option<&str>,
    profile_schema_keys: Option<&[String]>,
) -> Result<DocumentUnderstanding, String> {
    let hint = document_type_hint.unwrap_or("unspecified");
    let keys = profile_schema_keys
        .map(|k| k.join(", "))
        .unwrap_or_else(|| canonical_profile_keys().join(", ").to_string());

    let system = format!(
        r#"You analyze OCR text from identity or household documents.

Return ONE JSON object with this exact shape:
{{
  "document_type": string (snake_case, e.g. drivers_license, passport, insurance_card, tax_form, other),
  "document_type_confidence": number 0.0-1.0,
  "issuer_region": string or null (e.g. US-TX),
  "display_name_hint": string or null (for driver's licenses: the full name on the card),
  "fields": [
    {{ "key": string, "value": string, "confidence": number 0.0-1.0 }}
  ]
}}

Use ONLY these profile field keys when applicable: {keys}.

For US driver's licenses map at minimum when visible:
display_name (full name on card), legal_first_name, legal_last_name, legal_middle_name,
date_of_birth (MM/DD/YYYY), address_line1, city, state, postal_code,
drivers_license_number, drivers_license_state, drivers_license_issue_date, drivers_license_expiry.

Do not invent values. Fix obvious OCR typos when confident."#
    );

    let trimmed = ocr_text.chars().take(24_000).collect::<String>();
    let user = format!("User-selected document hint: {hint}\n\nOCR text:\n{trimmed}");

    let raw = llm_ocr_map::chat_json_object(
        api_key,
        &openai_base_url(),
        &openai_model(),
        &system,
        &user,
    )
    .await?;

    parse_understand_value(&raw)
}

fn parse_understand_value(v: &Value) -> Result<DocumentUnderstanding, String> {
    let obj = v
        .as_object()
        .ok_or_else(|| "LLM JSON must be an object".to_string())?;

    let document_type = obj
        .get("document_type")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or("other")
        .to_string();

    let document_type_confidence = obj
        .get("document_type_confidence")
        .and_then(json_f64)
        .unwrap_or(0.5)
        .clamp(0.0, 1.0);

    let issuer_region = obj
        .get("issuer_region")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string);

    let display_name_hint = obj
        .get("display_name_hint")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string);

    let fields = obj
        .get("fields")
        .and_then(|f| serde_json::from_value::<Vec<UnderstandField>>(f.clone()).ok())
        .unwrap_or_default()
        .into_iter()
        .filter(|f| !f.key.trim().is_empty() && !f.value.trim().is_empty())
        .map(|mut f| {
            f.key = normalize_field_key(&f.key);
            f.confidence = f.confidence.clamp(0.0, 1.0);
            f
        })
        .collect();

    Ok(DocumentUnderstanding {
        document_type,
        document_type_confidence,
        issuer_region,
        fields,
        display_name_hint,
    })
}

fn json_f64(v: &Value) -> Option<f64> {
    match v {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_understand_value_accepts_fields_array() {
        let v: Value = serde_json::from_str(
            r#"{
            "document_type": "drivers_license",
            "document_type_confidence": 0.91,
            "fields": [{"key":"display_name","value":"Jane Doe","confidence":0.88}]
        }"#,
        )
        .unwrap();
        let out = parse_understand_value(&v).unwrap();
        assert_eq!(out.document_type, "drivers_license");
        assert_eq!(out.fields.len(), 1);
    }

    #[test]
    fn normalize_maps_legacy_keys() {
        use dreamwork_core::profile_keys::normalize_field_key;
        assert_eq!(normalize_field_key("first_name"), "legal_first_name");
        assert_eq!(normalize_field_key("address_line_1"), "address_line1");
    }

    #[test]
    fn api_key_prefers_header() {
        let _guard = EnvGuard::clear_keys();
        let k = api_key_from_env_or_header(Some("hdr-key"));
        assert_eq!(k.as_deref(), Some("hdr-key"));
    }

    struct EnvGuard {
        dreamwork: Option<String>,
        openai: Option<String>,
    }

    impl EnvGuard {
        fn clear_keys() -> Self {
            let dreamwork = std::env::var("DREAMWORK_OPENAI_API_KEY").ok();
            let openai = std::env::var("OPENAI_API_KEY").ok();
            std::env::remove_var("DREAMWORK_OPENAI_API_KEY");
            std::env::remove_var("OPENAI_API_KEY");
            Self { dreamwork, openai }
        }
    }

    impl Drop for EnvGuard {
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
