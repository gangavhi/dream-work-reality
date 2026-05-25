# Build 35 Document Intelligence Implementation

**Date:** 2026-05-25  
**Scope:** iOS-first, zero-egress document understanding improvements for scan/upload → classification → extraction → review → profile/autofill.

## Summary

Build 35 implements the next local document-intelligence layer:

1. Structured documents use template matching, coordinate regions, and regex validation.
2. Semi-structured documents use OCR label detection, semantic synonyms, and local embedding-style matching.
3. Unknown/layout-heavy documents use chunked, layout-aware on-device extraction through the existing Rust mapper seam.
4. Review UI now exposes pipeline telemetry in DEBUG and when TestFlight/Release scans produce no fields.
5. Utility bill, bank statement, and visa extraction now get document-type-aware schema key narrowing.
6. GGUF runtime readiness is surfaced end-to-end, but true GGUF token inference is blocked because the repo does not contain a bundled `.gguf` model or llama.cpp-class runtime dependency.

## Files Implemented

### iOS Pipeline

| File | Change |
|---|---|
| `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/DocumentIntelligenceOrchestrator.swift` | Reordered trace to include classification, schema narrowing, template hit/miss, strategy, extraction, runtime status, confidence, and identity graph. |
| `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/ExtractionAgent.swift` | Accepts classification, template match, and strategy; branches into structured template extraction, chunked layout-aware extraction, or open-vocabulary semantic extraction. |
| `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/ExtractionStrategyAgent.swift` | New strategy engine: `structured`, `semiStructured`, or `layoutAI`. |
| `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/DocumentTemplateAgent.swift` | Template matcher/extractor for MVP docs, with driver-license coordinate regions and regex validation. |
| `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/LayoutAwareSemanticExtractor.swift` | Chunking + layout-context extraction facade for unknown documents; uses local `OnDeviceFieldMapper`. |
| `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/LayoutIntelligenceAgent.swift` | Carries OCR blocks with bounding boxes into downstream template extraction. |

### Field Mapping / Schema

| File | Change |
|---|---|
| `apps/ios/DreamWorkApp/Sources/Core/ProfileSchemaKeysForDocument.swift` | Added `visa`; expanded `utility_bill` and `bank_statement` schema keys (`account_number`, `amount_due`, `due_date`, `statement_period`, `ending_balance`, etc.). |
| `apps/ios/DreamWorkApp/Sources/Intelligence/Embeddings/SemanticFieldLabelMapper.swift` | Added document-type-aware label resolution so `Carrier` maps to `insurance_carrier` on insurance cards and date labels map correctly by document context. |
| `apps/ios/DreamWorkApp/Sources/Intelligence/Embeddings/LocalEmbeddingFieldMatcher.swift` | New offline token-vector matcher for semantically similar labels until MiniLM/CoreML ships. |
| `apps/ios/DreamWorkApp/Sources/Core/OcrLayoutSerializer.swift` | Expanded label vocabulary for insurance, bank, utility, visa, and billing labels to improve label/value pairing. |
| `apps/ios/DreamWorkApp/Sources/Core/DocumentTypePresentation.swift` | Recognizes `visa` open type for presentation. |

### GGUF Runtime Status

| File | Change |
|---|---|
| `core/dreamwork_core/src/local_document_mapper.rs` | Adds `llm_runtime_status` to mapper response. Current follow-up work now calls llama.cpp/Metal through Rust/C FFI and reports `gguf_metal_active` only after generation returns usable fields. |
| `apps/ios/DreamWorkApp/Sources/Core/OnDeviceFieldMapper.swift` | Decodes mapper engine/artifact/GGUF/runtime metadata and passes it into pipeline trace. |
| `apps/ios/DreamWorkApp/Sources/Core/BundledModelStore.swift` | Existing manifest lookup remains the model artifact source. No `.gguf` file is bundled in `Resources`; manifest points to optional `Qwen2.5-3B-Instruct-Q4_K_M.gguf`. |

### Review UI Telemetry

| File | Change |
|---|---|
| `apps/ios/DreamWorkApp/Sources/Core/ScanReviewEnrichment.swift` | Adds `pipelineTrace`. |
| `apps/ios/DreamWorkApp/Sources/Core/ScanReviewPayload.swift` | Adds `pipelineTrace`. |
| `apps/ios/DreamWorkApp/Sources/Core/CoreBridgeService.swift` | Carries extraction trace through scan enrichment. |
| `apps/ios/DreamWorkApp/Sources/Core/AppState.swift` | Passes trace to review payload. |
| `apps/ios/DreamWorkApp/Sources/Features/Scan/ScanReviewView.swift` | Shows pipeline telemetry in DEBUG and when no fields are detected; includes mapping-source summary and trace text. |

### Tests / Diagnostics

| File | Change |
|---|---|
| `apps/ios/DreamWorkAppTests/IntelligenceModuleTests.swift` | Tests template extraction, coordinate extraction, strategy branching, schema narrowing, embedding-style label matching, chunking, learning, and canonical autofill payloads. |
| `apps/ios/DreamWorkAppTests/DocumentIntelligencePipelineTests.swift` | Tests classification → template → identity graph pipeline trace. |
| `apps/ios/DreamWorkAppTests/DocumentFieldIdentificationDiagnosticsTests.swift` | Simulator diagnostic test that prints stage-by-stage evidence for representative field-identification failures. |

## Runtime Reality: GGUF

Requested item: **“Ship bundled GGUF inference (ADR 0017) wired to OnDeviceFieldMapper / local_document_mapper.rs — replace heuristic-only default.”**

Current evidence:

- `apps/ios/DreamWorkApp/Resources/model-manifest.json` references `Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- No `.gguf` artifact exists under `apps/ios/DreamWorkApp/Resources`.
- `apps/ios/project.yml` links `Vendor/llama.xcframework`.
- `apps/ios/DreamWorkApp/Sources/Native/LlamaCppBridge.mm` calls llama.cpp directly through the framework C API.
- `core/dreamwork_core/src/inference/llama_cpp.rs` binds Rust to that app-provided C ABI.
- `core/dreamwork_core/src/inference/gguf.rs` only parses GGUF headers.

Implemented now:

- If a GGUF file is present/header-valid and llama.cpp returns usable schema JSON, the Rust mapper reports `llm_runtime_status = "gguf_metal_active"`.
- iOS includes that status in `pipelineTrace` as `runtime:<engine>:<artifact>:gguf_present=...`.
- The mapper does not silently claim LLM inference. It keeps the deterministic heuristic/template/semantic path when model load/generation fails or returns no fields.

Remaining blocker:

- To make this production-ready, we must QA with real device scans, tune prompts/context/generation limits, and benchmark memory/thermal behavior.

## Diagnostic Evidence

The simulator diagnostic test prints records prefixed with `DIAG|`.

Example findings before the latest context fixes:

- Insurance card classified correctly but `Carrier` could map to utility provider because synonyms were not document-type-aware.
- Passport `Date of Issue` mapped to driver-license issue date because label mapping ignored document context.
- Driver license `Date of Expiry` could also appear as passport expiry because generic expiry mapping was passport-biased.
- Visa was not classified at all because `ProfileSchemaKeysForDocument.inferOpenType` did not recognize `VISA`.
- Rust mapper could infer display name from OCR block lines too aggressively, e.g. treating document headers as names.

Build 35 addresses the Swift-side context mapping and schema narrowing. The remaining Rust-name overreach is now visible in telemetry and should be tightened next inside `local_document_mapper.rs`.

## Verification

Commands run:

```bash
cd apps/ios
xcodegen generate
xcodebuild test -quiet -scheme DreamWorkApp \
  -destination 'platform=iOS Simulator,id=1253C9D2-75D7-4DBC-BEC6-A530DDE933B1' \
  -only-testing:DreamWorkAppTests/IntelligenceModuleTests \
  -only-testing:DreamWorkAppTests/DocumentIntelligencePipelineTests \
  -only-testing:DreamWorkAppTests/DocumentFieldIdentificationDiagnosticsTests
```

```bash
cd core/dreamwork_core
cargo test local_document_mapper -- --nocapture
```

Status:

- Focused iOS intelligence tests passed.
- Rust local document mapper tests passed.
- Existing warnings remain unrelated: Rust `normalize_dob` unused and Xcode script-output warnings.

## Published Location

This implementation note is published in-repo at:

`docs/build-35-document-intelligence-implementation.md`
