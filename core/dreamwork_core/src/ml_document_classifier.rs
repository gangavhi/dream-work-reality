use serde::{Deserialize, Serialize};

use crate::inference::{generate_constrained_json, InferenceError};

pub const CLASSIFIER_ENGINE_ID: &str = "llm.document_classifier.v1";

#[derive(Debug, Clone, Deserialize)]
pub struct ClassifyDocumentRequest {
    pub layout_text: String,
    #[serde(default)]
    pub model_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClassifyDocumentResponse {
    pub document_type: String,
    pub display_label: String,
    pub confidence: f64,
    pub engine: String,
    pub status: String,
}

#[derive(Debug, Clone, Deserialize)]
struct LlmClassifyDocumentResponse {
    document_type: String,
    #[serde(default)]
    display_label: String,
    #[serde(default)]
    confidence: f64,
}

pub fn classify_document_from_json(json: &str) -> Result<ClassifyDocumentResponse, String> {
    let req: ClassifyDocumentRequest =
        serde_json::from_str(json).map_err(|e| format!("invalid JSON: {e}"))?;
    Ok(classify_document(&req))
}

pub fn classify_document(req: &ClassifyDocumentRequest) -> ClassifyDocumentResponse {
    let Some(model_path) = req.model_path.as_deref().filter(|p| !p.trim().is_empty()) else {
        return failed("classifier_model_missing");
    };
    if !std::path::Path::new(model_path).is_file() {
        return failed("classifier_model_missing");
    }

    match generate_constrained_json(model_path, &classification_prompt(&req.layout_text), 192)
        .and_then(|json| parse_response(&json))
    {
        Ok(mut response) => {
            response.engine = CLASSIFIER_ENGINE_ID.to_string();
            response.status = "classifier_active".to_string();
            response.document_type = normalize_type(&response.document_type);
            if response.display_label.trim().is_empty() {
                response.display_label = response.document_type.replace('_', " ");
            }
            response
        }
        Err(err) => failed(&format!(
            "classifier_generation_failed:{}",
            status_reason(&err)
        )),
    }
}

fn parse_response(json: &str) -> Result<ClassifyDocumentResponse, InferenceError> {
    let llm = serde_json::from_str::<LlmClassifyDocumentResponse>(json)
        .map_err(|e| InferenceError::Session(format!("invalid classifier JSON: {e}")))?;
    Ok(ClassifyDocumentResponse {
        document_type: llm.document_type,
        display_label: llm.display_label,
        confidence: llm.confidence,
        engine: String::new(),
        status: String::new(),
    })
}

fn classification_prompt(layout_text: &str) -> String {
    format!(
        r#"Classify this OCR/layout text into an open-vocabulary document type.

Rules:
- Return only JSON.
- Use this exact shape:
  {{"document_type":"snake_case_type","display_label":"Human label","confidence":0.0}}
- Do not use keyword rules outside the model; infer from all OCR evidence.
- If uncertain, return document_type "unknown" with low confidence.

OCR/layout text:
{}"#,
        layout_text
    )
}

fn failed(status: &str) -> ClassifyDocumentResponse {
    ClassifyDocumentResponse {
        document_type: "unknown".to_string(),
        display_label: "Document classifier failed".to_string(),
        confidence: 0.0,
        engine: CLASSIFIER_ENGINE_ID.to_string(),
        status: status.to_string(),
    }
}

fn normalize_type(value: &str) -> String {
    let normalized = value
        .trim()
        .to_lowercase()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect::<String>();
    let compact = normalized
        .split('_')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("_");
    if compact.is_empty() {
        "unknown".to_string()
    } else {
        compact
    }
}

fn status_reason(err: &InferenceError) -> String {
    err.to_string()
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.') {
                c.to_ascii_lowercase()
            } else {
                '_'
            }
        })
        .collect::<String>()
        .trim_matches('_')
        .chars()
        .take(96)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_model_fails_closed() {
        let resp = classify_document(&ClassifyDocumentRequest {
            layout_text: "Passport".to_string(),
            model_path: None,
        });
        assert_eq!(resp.document_type, "unknown");
        assert_eq!(resp.status, "classifier_model_missing");
        assert_eq!(resp.confidence, 0.0);
    }
}
