//! Cross-module smoke test: OCR seam → inference stubs → mapping validator.

use dreamwork_core::{
    extraction::{flatten_normalized_document, materialize_from_ocr},
    inference::{GenerativeArtifactId, GenerativeLlmSession, StubGenerativeSession},
    ocr::{EnglishStubOcrEngine, OcrEngine},
    schema::{
        DefaultMappingPlanValidator, FieldMapping, MappingOp, MappingPlan, MappingPlanValidator,
    },
};

#[test]
fn stub_pipeline_produces_valid_mapping_plan_shape() {
    let ocr = EnglishStubOcrEngine;
    assert_eq!(ocr.meta().language_tag, "en");

    let doc = ocr.recognize_document_en(&[]).unwrap();
    let blob = serde_json::to_string(&doc).unwrap();

    let llm = StubGenerativeSession {
        id: GenerativeArtifactId("llm.schema.standard.v1".to_string()),
    };
    let json = llm.generate_schema_plan_json(&blob).unwrap();
    let _parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

    let flat = flatten_normalized_document(&doc);
    assert!(
        flat.contains_key("ocr.full_text"),
        "flatten should expose ocr.full_text"
    );

    let plan = MappingPlan {
        mappings: vec![FieldMapping {
            source_key: "ocr.page.0.block.0".to_string(),
            target_field: "person.display_name".to_string(),
            op: MappingOp::Copy,
        }],
    };
    DefaultMappingPlanValidator.validate(&plan).unwrap();
    let fields = materialize_from_ocr(&plan, &doc).unwrap();
    assert!(
        fields
            .get("person.display_name")
            .map(|s| !s.is_empty())
            .unwrap_or(false),
        "mapped display name should come from first OCR block"
    );
}
