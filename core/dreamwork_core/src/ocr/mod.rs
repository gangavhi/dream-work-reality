//! On-device OCR abstraction (ADR 0004). English-only default tagging (ADR 0018).
//!
//! Platform engines (Vision, ML Kit) integrate behind [`OcrEngine`] without changing ingest contracts.

use serde::{Deserialize, Serialize};

/// BCP-47 tag recorded on extraction runs (`en` for v1).
pub type LanguageTag = String;

/// Stable identifier for provenance (e.g. `vision.en.v1`, `mlkit_latin.en.v1`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OcrEngineId(pub String);

/// Normalized bounding box in **normalized page coordinates** (0..1), origin top-left.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NormRect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TextBlock {
    pub text: String,
    pub confidence: f32,
    pub bounds: NormRect,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Page {
    pub blocks: Vec<TextBlock>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NormalizedDocument {
    pub pages: Vec<Page>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OcrError {
    UnsupportedInput(String),
    Engine(String),
}

impl std::fmt::Display for OcrError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OcrError::UnsupportedInput(s) => write!(f, "unsupported OCR input: {s}"),
            OcrError::Engine(s) => write!(f, "OCR engine error: {s}"),
        }
    }
}

impl std::error::Error for OcrError {}

/// Immutable metadata stored beside OCR output for audits (ADR 0004).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExtractionRunMeta {
    pub engine_id: OcrEngineId,
    pub model_revision: String,
    pub language_tag: LanguageTag,
}

pub trait OcrEngine: Send + Sync {
    fn meta(&self) -> ExtractionRunMeta;

    /// Raster bytes interpreted as engine-specific default (typically PNG/JPEG); stubs may ignore payload shape.
    fn recognize_document_en(&self, image_bytes: &[u8]) -> Result<NormalizedDocument, OcrError>;
}

/// Deterministic stub for CI/unit tests and simulator flows without camera pipelines.
#[derive(Debug, Default)]
pub struct EnglishStubOcrEngine;

impl EnglishStubOcrEngine {
    pub const ENGINE_ID: &'static str = "stub.english.v1";
}

impl OcrEngine for EnglishStubOcrEngine {
    fn meta(&self) -> ExtractionRunMeta {
        ExtractionRunMeta {
            engine_id: OcrEngineId(Self::ENGINE_ID.to_string()),
            model_revision: "stub".to_string(),
            language_tag: "en".to_string(),
        }
    }

    fn recognize_document_en(&self, image_bytes: &[u8]) -> Result<NormalizedDocument, OcrError> {
        let hint = if image_bytes.is_empty() {
            "(empty)"
        } else {
            "non-empty raster"
        };
        Ok(NormalizedDocument {
            pages: vec![Page {
                blocks: vec![TextBlock {
                    text: format!("stub OCR output ({hint})"),
                    confidence: 1.0,
                    bounds: NormRect {
                        x: 0.0,
                        y: 0.0,
                        width: 1.0,
                        height: 0.1,
                    },
                }],
            }],
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stub_engine_reports_en_metadata() {
        let engine = EnglishStubOcrEngine;
        assert_eq!(engine.meta().language_tag, "en");
        assert_eq!(engine.meta().engine_id.0, EnglishStubOcrEngine::ENGINE_ID);
    }

    #[test]
    fn stub_engine_returns_single_page() {
        let doc = EnglishStubOcrEngine
            .recognize_document_en(&[1, 2, 3])
            .unwrap();
        assert_eq!(doc.pages.len(), 1);
        assert!(!doc.pages[0].blocks[0].text.is_empty());
    }
}
