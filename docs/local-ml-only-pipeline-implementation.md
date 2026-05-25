# Local ML-Only Pipeline Implementation

**Date:** 2026-05-25

This build converts the document intelligence path to fail-closed local ML for classification,
field parsing, and SQLite storage planning.

## Model Choices

- Document type classification: `bartowski/Qwen2.5-3B-Instruct-GGUF` using
  `Qwen2.5-3B-Instruct-Q4_K_M.gguf`. This reuses the already selected mobile-suitable
  GGUF/Metal runtime and supports open-vocabulary document labels from OCR/layout text.
- Field/data parsing: `bartowski/Qwen2.5-3B-Instruct-GGUF` through the existing
  `llm.schema.lite.v1` parser path.
- SQLite storage planning: `saadxsalman/SS-350M-SQL-Strict-GGUF` using
  `SS-350M-SQL-Strict.Q8_0.gguf`. This is a compact GGUF text-to-SQL/storage reasoning
  model intended for edge/local database tasks.

## Fail-Closed Runtime Rules

- `ClassificationAgent` calls `dreamwork_classify_document_json`; it no longer uses barcode/MRZ
  source checks or `ProfileSchemaKeysForDocument.inferOpenType(from:)`.
- `ExtractionAgent` only calls `OnDeviceFieldMapper`; it no longer runs template extraction,
  machine-readable extraction, `LayoutAwareSemanticExtractor`, or learned correction replay.
- `storage_routing.rs` no longer routes by canonical key membership. It requires a local storage
  planner model and returns an empty plan with `planner_status` when the model is missing or fails.
- The review enrichment path appends classifier/parser/storage model failures to `mappingNotice`
  and `pipelineTrace`.

## Local Model Install

```bash
apps/ios/scripts/download-qwen-gguf-model.sh
apps/ios/scripts/download-storage-planner-gguf-model.sh
apps/ios/scripts/install-gguf-model-to-booted-simulator.sh
```
