# Apple-native document intelligence (ganga-2026-05-16-3)

## Principles

- **Vision** (`VNRecognizeTextRequest`) for OCR — runs out-of-process; skew correction built in.
- **Vision** barcodes + MRZ heuristics for machine-readable payloads.
- **NaturalLanguage** for language ID, NER-style tagging, and **NLEmbedding** label→profile-key mapping.
- **Create ML** (optional): drop trained `.mlmodel` / `.mlmodelc` into the app bundle; registry loads them when present.
- **Rust FFI** retained for SQLite persistence (`manual_entry`, OCR ingest, person resolution, optional `applyStoragePlan`) — no GGUF/ONNX on this branch.

## Pipeline (orchestrator-centric)

`DocumentIntelligencePipeline` delegates to **`DocumentIntelligenceOrchestrator`** (merged from `ganga-2026-05-16-2`), with ONNX/GGUF/llama paths removed:

1. `VisionOcrAdapter` + `OcrEngine` — normalized blocks
2. `EmbeddedPayloadHints` — barcode + MRZ
3. `LocalDocumentClassifier` → `NLDocumentClassifier` (+ optional Create ML)
4. `ExtractionAgent` — MRZ/barcode, `AppleSemanticFieldExtractor`, specialized parsers, optional network `GenAIFieldMapper`
5. `DocumentValidationPipeline` + `ConfidenceOrchestrator` + `AddressFieldMerger`
6. `SchemaMappingEngine` — standardized output
7. `DocumentKnowledgeGraph` — identity graph / autofill
8. On save: `CoreIngestFFI.resolvePerson` + **`AppleStoragePlanner`** (+ optional Rust `applyStoragePlan`)

Supporting modules under `Sources/AppleNative/`: `NLFieldLabelMapper`, `AppleSemanticFieldExtractor`, `AppleProfileBuilder`, `AppleStoragePlanner`, `CreateMLModelRegistry`.

## Create ML (Xcode)

Train in Xcode → Create ML:

- **Text Classifier** → document type (`drivers_license`, `passport`, …)
- **Word Tagger** → BIO tags for field labels on OCR lines

Export and add to `DreamWorkApp/Resources/MLModels/` with names referenced in `CreateMLModelRegistry.swift`.

## Removed from default path

- MiniLM ONNX, GGUF llama.cpp, PaddleOCR adapters, `OnDeviceFieldMapper`, `LayoutAwareSemanticExtractor`
- Network LLM (`GenAIFieldMapper`) — optional via Settings only (`ollama` / `openAI`)
- Rust `dreamwork_plan_storage_json` LLM planner — replaced by `AppleStoragePlanner` on scan save
