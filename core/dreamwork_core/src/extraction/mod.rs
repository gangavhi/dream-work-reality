//! OCR extraction persistence helpers (ADR 0004): flatten normalized documents for mapping plans.

use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

use rand_core::{OsRng, RngCore};

use crate::ocr::{ExtractionRunMeta, NormalizedDocument, OcrEngineId};
use crate::schema::{apply_mapping_plan, MappingPlan, ValidationError};

/// One persisted OCR extraction run (document + provenance).
#[derive(Debug, Clone, PartialEq)]
pub struct ExtractionRunRecord {
    pub id: String,
    pub created_at_ms: i64,
    pub meta: ExtractionRunMeta,
    pub document: NormalizedDocument,
}

impl ExtractionRunRecord {
    pub fn new(document: NormalizedDocument, meta: ExtractionRunMeta) -> Self {
        Self {
            id: new_extraction_run_id(),
            created_at_ms: now_ms(),
            meta,
            document,
        }
    }
}

pub fn default_import_meta() -> ExtractionRunMeta {
    ExtractionRunMeta {
        engine_id: OcrEngineId("platform.normalized_json.v1".into()),
        model_revision: "import".into(),
        language_tag: "en".into(),
    }
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn new_extraction_run_id() -> String {
    let mut b = [0u8; 16];
    OsRng.fill_bytes(&mut b);
    format!("exr_{}", hex::encode(b))
}

/// Flatten [`NormalizedDocument`] into stable keys for [`MappingPlan`] sources.
///
/// Keys include `ocr.page.{p}.block.{b}` per block and `ocr.full_text` (blocks joined with newlines).
pub fn flatten_normalized_document(doc: &NormalizedDocument) -> HashMap<String, String> {
    let mut m = HashMap::new();
    let mut full = String::new();
    for (pi, page) in doc.pages.iter().enumerate() {
        for (bi, block) in page.blocks.iter().enumerate() {
            let key = format!("ocr.page.{pi}.block.{bi}");
            m.insert(key, block.text.clone());
            if !full.is_empty() {
                full.push('\n');
            }
            full.push_str(&block.text);
        }
    }
    m.insert("ocr.full_text".to_string(), full);
    m
}

/// Validate `plan`, flatten `doc`, and apply mappings into target field keys.
pub fn materialize_from_ocr(
    plan: &MappingPlan,
    doc: &NormalizedDocument,
) -> Result<HashMap<String, String>, ValidationError> {
    let flat = flatten_normalized_document(doc);
    apply_mapping_plan(plan, &flat)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ocr::{NormRect, Page, TextBlock};
    use crate::schema::{
        DefaultMappingPlanValidator, FieldMapping, MappingOp, MappingPlan, MappingPlanValidator,
    };

    #[test]
    fn flatten_joins_full_text_and_indexes_blocks() {
        let doc = NormalizedDocument {
            pages: vec![Page {
                blocks: vec![
                    TextBlock {
                        text: "a".into(),
                        confidence: 1.0,
                        bounds: NormRect {
                            x: 0.0,
                            y: 0.0,
                            width: 1.0,
                            height: 0.1,
                        },
                    },
                    TextBlock {
                        text: "b".into(),
                        confidence: 1.0,
                        bounds: NormRect {
                            x: 0.0,
                            y: 0.1,
                            width: 1.0,
                            height: 0.1,
                        },
                    },
                ],
            }],
        };
        let flat = flatten_normalized_document(&doc);
        assert_eq!(
            flat.get("ocr.page.0.block.0").map(String::as_str),
            Some("a")
        );
        assert_eq!(
            flat.get("ocr.page.0.block.1").map(String::as_str),
            Some("b")
        );
        assert_eq!(flat.get("ocr.full_text").map(String::as_str), Some("a\nb"));
    }

    #[test]
    fn materialize_applies_trim_and_copy() {
        let doc = NormalizedDocument {
            pages: vec![Page {
                blocks: vec![TextBlock {
                    text: "  hello  ".into(),
                    confidence: 1.0,
                    bounds: NormRect {
                        x: 0.0,
                        y: 0.0,
                        width: 1.0,
                        height: 0.1,
                    },
                }],
            }],
        };
        let plan = MappingPlan {
            mappings: vec![
                FieldMapping {
                    source_key: "ocr.page.0.block.0".into(),
                    target_field: "raw".into(),
                    op: MappingOp::Copy,
                },
                FieldMapping {
                    source_key: "ocr.page.0.block.0".into(),
                    target_field: "trimmed".into(),
                    op: MappingOp::Trim,
                },
            ],
        };
        DefaultMappingPlanValidator.validate(&plan).unwrap();
        let out = materialize_from_ocr(&plan, &doc).unwrap();
        assert_eq!(out.get("raw").map(String::as_str), Some("  hello  "));
        assert_eq!(out.get("trimmed").map(String::as_str), Some("hello"));
    }
}
