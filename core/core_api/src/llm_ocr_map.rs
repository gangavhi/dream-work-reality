//! Map raw OCR text to structured string fields using an OpenAI-compatible Chat Completions API.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<Message>,
    temperature: f32,
    #[serde(skip_serializing_if = "Option::is_none")]
    response_format: Option<ResponseFormat>,
}

#[derive(Serialize)]
struct ResponseFormat {
    #[serde(rename = "type")]
    typ: String,
}

#[derive(Serialize)]
struct Message {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct ChatResponse {
    choices: Vec<Choice>,
}

#[derive(Deserialize)]
struct Choice {
    message: Msg,
}

#[derive(Deserialize)]
struct Msg {
    content: String,
}

/// Low-level chat call with `response_format: json_object`, returning parsed JSON (Stage 1 understanding).
pub async fn chat_json_object(
    api_key: &str,
    base_url: &str,
    model: &str,
    system: &str,
    user: &str,
) -> Result<Value, String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(120))
        .build()
        .map_err(|e| e.to_string())?;

    let url = format!("{}/chat/completions", base_url.trim_end_matches('/'));

    let body = ChatRequest {
        model: model.to_string(),
        messages: vec![
            Message {
                role: "system".into(),
                content: system.into(),
            },
            Message {
                role: "user".into(),
                content: user.into(),
            },
        ],
        temperature: 0.1,
        response_format: Some(ResponseFormat {
            typ: "json_object".into(),
        }),
    };

    let res = client
        .post(&url)
        .header("Authorization", format!("Bearer {api_key}"))
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;

    let status = res.status();
    if !status.is_success() {
        let t = res.text().await.unwrap_or_default();
        return Err(format!(
            "LLM HTTP error: {} — {}",
            status,
            t.chars().take(800).collect::<String>()
        ));
    }

    let parsed: ChatResponse = res.json().await.map_err(|e| e.to_string())?;
    let content = parsed
        .choices
        .first()
        .ok_or_else(|| "LLM returned no choices".to_string())?
        .message
        .content
        .trim()
        .to_string();

    let json_str = strip_markdown_json_fence(&content);
    serde_json::from_str(&json_str).map_err(|e| format!("invalid JSON from model: {e}"))
}

/// Calls `POST {base_url}/chat/completions` and parses the assistant message as a JSON object
/// of string fields suitable for `manual_fields` / form fill (same key names as `/genai/extract-document` where possible).
pub async fn map_ocr_to_string_map(
    api_key: &str,
    base_url: &str,
    model: &str,
    raw_text: &str,
    document_hint: Option<&str>,
    use_json_object_mode: bool,
) -> Result<BTreeMap<String, String>, String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(120))
        .build()
        .map_err(|e| e.to_string())?;

    let url = format!("{}/chat/completions", base_url.trim_end_matches('/'));

    let hint = document_hint.unwrap_or("unspecified document");
    let system = r#"You map noisy OCR text from identity or administrative documents into flat JSON fields.

Return one JSON object only. Omit keys you cannot infer. Values must be strings — no nested objects or arrays.

For US driver's licenses use these canonical keys when visible:
display_name (full name on the card — the driver's name),
legal_first_name, legal_middle_name, legal_last_name,
date_of_birth (MM/DD/YYYY),
address_line1, city, state (2-letter), postal_code,
drivers_license_number, drivers_license_state,
drivers_license_issue_date, drivers_license_expiry (MM/DD/YYYY).

Legacy aliases also accepted: first_name, last_name, document_number, issue_mmddyyyy, expiry_mmddyyyy.

Fix obvious OCR typos when confident. Do not invent values."#;

    let trimmed = raw_text.chars().take(24_000).collect::<String>();
    let user = format!("Document hint: {hint}\n\nOCR text:\n{trimmed}");

    let body = ChatRequest {
        model: model.to_string(),
        messages: vec![
            Message {
                role: "system".into(),
                content: system.into(),
            },
            Message {
                role: "user".into(),
                content: user,
            },
        ],
        temperature: 0.1,
        response_format: use_json_object_mode.then(|| ResponseFormat {
            typ: "json_object".into(),
        }),
    };

    let res = client
        .post(&url)
        .header("Authorization", format!("Bearer {api_key}"))
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;

    let status = res.status();
    if !status.is_success() {
        let t = res.text().await.unwrap_or_default();
        return Err(format!(
            "LLM HTTP error: {} — {}",
            status,
            t.chars().take(800).collect::<String>()
        ));
    }

    let parsed: ChatResponse = res.json().await.map_err(|e| e.to_string())?;
    let content = parsed
        .choices
        .first()
        .ok_or_else(|| "LLM returned no choices".to_string())?
        .message
        .content
        .trim()
        .to_string();

    let json_str = strip_markdown_json_fence(&content);
    let v: Value = serde_json::from_str(&json_str).map_err(|e| format!("invalid JSON from model: {e}"))?;
    let obj = v
        .as_object()
        .ok_or_else(|| "LLM JSON must be an object".to_string())?;

    let mut out = BTreeMap::new();
    for (k, val) in obj {
        match val {
            Value::String(s) => {
                let t = s.trim();
                if !t.is_empty() {
                    out.insert(k.clone(), t.to_string());
                }
            }
            Value::Number(n) => {
                out.insert(k.clone(), n.to_string());
            }
            Value::Bool(b) => {
                out.insert(k.clone(), b.to_string());
            }
            _ => {}
        }
    }
    Ok(out)
}

pub(crate) fn strip_markdown_json_fence(s: &str) -> String {
    let t = s.trim();
    if let Some(rest) = t.strip_prefix("```json") {
        return strip_trailing_fence(rest.trim_start());
    }
    if let Some(rest) = t.strip_prefix("```") {
        return strip_trailing_fence(rest.trim_start());
    }
    t.to_string()
}

fn strip_trailing_fence(s: &str) -> String {
    if let Some(i) = s.rfind("```") {
        s[..i].trim().to_string()
    } else {
        s.to_string()
    }
}
