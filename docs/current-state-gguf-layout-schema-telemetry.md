# Current State: GGUF, Layout Pairing, Schema Narrowing, Telemetry

**Date:** 2026-05-25  
**Context:** Follow-up assessment for document identification and field/data extraction reliability.

This document analyzes the current codebase against four requested implementation areas:

1. Ship bundled GGUF inference per ADR 0017, wired to `OnDeviceFieldMapper` / `local_document_mapper.rs`.
2. Improve layout pairing or LayoutLM artifact so `OpenVocabularyFieldExtractor` gets label/value pairs on unstructured scans.
3. Add document-type-aware schema narrowing for bank statements and utility bills.
4. Add telemetry in review UI showing `pipelineTrace` and mapping source when fields are empty.

## Executive Summary

| Area | Current Status | Bottom Line |
|---|---|---|
| GGUF inference | **LLM-only parser, fail-visible** | GGUF model is required for `local_document_mapper.rs`. If missing/invalid/generation fails, fields stay empty and telemetry/user notice report the LLM parser failure; no deterministic mapper fallback is used. |
| Layout pairing | **Heuristics disabled, LayoutLM selected** | Heuristic spatial label/value pairs are no longer emitted into model input or layout analysis. Selected HF model is `HYPJUDY/layoutlmv3-base-finetuned-funsd`; CoreML adapter remains pending. |
| Schema narrowing | **Removed** | Extraction now uses open vocabulary schema (`schema_keys:generic:any`) instead of narrowing for utility/bank/visa or any document type. |
| Review telemetry | **Implemented** | `ScanReviewView` shows pipeline telemetry in DEBUG and when no fields are detected in non-DEBUG builds. |

## 1. Bundled GGUF Inference

### Implemented

The selected GGUF model is pinned in the app manifest:

```json
{
  "artifact_id": "llm.schema.lite.v1",
  "filename": "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
  "bytes_approx": 1929903264,
  "sha256": "9c9f56a391a3abbd5b89d0245bf6106081bcc3173119d4229235dd9d23253f94",
  "download_url": "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf"
}
```

Files:

- `apps/ios/DreamWorkApp/Resources/model-manifest.json`
- `apps/ios/scripts/download-qwen-gguf-model.sh`
- `apps/ios/scripts/install-gguf-model-to-booted-simulator.sh`
- `apps/ios/scripts/install-llama-xcframework.sh`
- `docs/qwen-gguf-model-installation.md`
- `docs/llama-cpp-metal-runtime-linking.md`

The local developer machine has the model at:

```text
~/Library/Application Support/DreamWork/models/Qwen2.5-3B-Instruct-Q4_K_M.gguf
```

The booted simulator sandbox has a copy installed.

### Runtime Wiring

`OnDeviceFieldMapper` sends the model path from `BundledModelStore.liteArtifactPath()` into Rust:

```swift
let body = MapRequest(
    layout_text: String(trimmed.prefix(24_000)),
    profile_schema_keys: profileSchemaKeys,
    model_path: BundledModelStore.liteArtifactPath()
)
```

File:

- `apps/ios/DreamWorkApp/Sources/Core/OnDeviceFieldMapper.swift`

Rust returns explicit runtime state:

```rust
pub const GGUF_METAL_ACTIVE: &str = "gguf_metal_active";
pub const GGUF_RUNTIME_PENDING: &str = "gguf_valid_llama_cpp_no_fields";
```

and runs llama.cpp generation when GGUF is header-valid:

```rust
if gguf_valid {
    match run_llama_schema_plan(req) {
        Ok(plan) => { /* apply parseable fields */ }
        Err(err) => { /* return empty fields + failure status */ }
    }
}
```

File:

- `core/dreamwork_core/src/local_document_mapper.rs`

### Current Blocker

True GGUF inference is now wired, but **not yet tuned or benchmarked for real device use**.

Evidence:

- `apps/ios/project.yml` links `Vendor/llama.xcframework`, and `apps/ios/DreamWorkApp/RustCore.xcconfig` links `Metal`, `Accelerate`, `Foundation`, and `libc++`.
- `apps/ios/DreamWorkApp/Sources/Native/LlamaCppBridge.mm` calls `llama_model_load_from_file`, `llama_init_from_model`, `llama_tokenize`, `llama_decode`, and the JSON grammar sampler.
- `core/dreamwork_core/src/inference/llama_cpp.rs` binds Rust to the C ABI wrapper.
- `OnDeviceGenerativeSession.generate_schema_plan_json(...)` now calls `generate_constrained_json(...)`.
- `local_document_mapper.rs` no longer seeds fields with deterministic extraction before llama.cpp.
- Failure states return empty fields with statuses such as `llm_document_parser_failed:model_missing`, `llm_document_parser_failed:model_invalid`, or `gguf_valid_llama_cpp_generation_failed:*`.

### Next Required Work

1. Run full physical-device tests with real scans and the installed Qwen GGUF model.
2. Tune prompt/context/max-token parameters for extraction quality and latency.
3. Add golden tests once CI/TestFlight can reliably supply the GGUF model artifact.
4. Benchmark memory pressure and thermal behavior on target iPhones.

## 2. Layout Pairing / LayoutLM

### Implemented

`OcrLayoutSerializer` currently supports:

- Same-row label left, value right.
- Vertical label above value.
- Inline label/value parsing with `:`.
- Inline special cases such as dates, passport number, names, nationality, gender.
- Expanded label vocabulary for insurance, bank, utility, billing, and visa labels.

Files:

- `apps/ios/DreamWorkApp/Sources/Core/OcrLayoutSerializer.swift`
- `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/LayoutIntelligenceAgent.swift`
- `apps/ios/DreamWorkApp/Sources/Intelligence/Embeddings/OpenVocabularyFieldExtractor.swift`

Expanded label vocabulary now includes:

```text
member number, subscriber id, group number, carrier, provider,
account number, statement period, opening balance, ending balance,
balance due, amount due, due date, billing period, service period,
meter number, visa number, visa type
```

`LayoutIntelligenceAgent` now passes raw layout blocks downstream:

```swift
struct LayoutDocument: Hashable {
    let layoutText: String
    let modelInput: String
    let blocks: [OcrLayoutSerializer.LayoutBlock]
    let labelValuePairs: [OcrLayoutSerializer.LabelValuePair]
    let engineID: String
}
```

This enables coordinate-template extraction in `DocumentTemplateAgent`.

### Current Model State

There is no bundled LayoutLM/CoreML artifact yet, and heuristic spatial pairing is intentionally disabled.

Evidence:

- `ModelArtifactRegistry` has a `layoutLM` slot.
- `LayoutIntelligenceAgent` reports `layout.model_missing` when the artifact is absent.
- `OcrLayoutSerializer.modelInput(...)` no longer appends heuristic `label | value` pairs.
- Selected model source is `HYPJUDY/layoutlmv3-base-finetuned-funsd`.

Therefore unstructured scans no longer depend on heuristic label/value pairing. Model-produced layout pairs will start only after the LayoutLMv3 CoreML adapter is implemented.

### Next Required Work

1. Convert `HYPJUDY/layoutlmv3-base-finetuned-funsd` to `layoutlmv3.mlmodelc`.
2. Add a CoreML adapter that classifies OCR tokens/boxes into form roles.
3. Feed only model-derived pairs into `OpenVocabularyFieldExtractor`.
4. Add golden layout tests for utility bill, insurance card, bank statement, and messy forms.

## 3. Generic Open Schema

### Implemented

Document-type-aware narrowing has been removed from extraction prompts.

`ProfileSchemaKeysForDocument.keys(...)` now returns an empty list, which means the mapper prompt stays open-vocabulary:

File:

- `apps/ios/DreamWorkApp/Sources/Core/ProfileSchemaKeysForDocument.swift`

The orchestrator now passes open schema keys:

```swift
let schemaKeys: [String] = []
trace.append("schema_keys:generic:any")
```

File:

- `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/DocumentIntelligenceOrchestrator.swift`

### Caveat

The LLM is now responsible for choosing document-specific keys from OCR evidence instead of being constrained by a document type.

## 4. Review UI Telemetry

### Implemented

`ScanReviewPayload` and `ScanReviewEnrichment` now carry:

```swift
let pipelineTrace: [String]
```

Files:

- `apps/ios/DreamWorkApp/Sources/Core/ScanReviewPayload.swift`
- `apps/ios/DreamWorkApp/Sources/Core/ScanReviewEnrichment.swift`
- `apps/ios/DreamWorkApp/Sources/Core/CoreBridgeService.swift`
- `apps/ios/DreamWorkApp/Sources/Core/AppState.swift`

`ScanReviewView` shows telemetry:

- Always in DEBUG.
- In non-DEBUG/TestFlight-like builds when fields are empty.

```swift
private var shouldShowTelemetry: Bool {
    #if DEBUG
    return true
    #else
    return payload.suggestions.isEmpty
    #endif
}
```

Telemetry includes:

- Mapping source summary.
- Pipeline trace.
- Empty-field explanatory message.

File:

- `apps/ios/DreamWorkApp/Sources/Features/Scan/ScanReviewView.swift`

Example trace entries include:

```text
ocr:vision.en.v1
layout:layout.model_missing
classify:heuristic.on_device.v1
schema_keys:generic:any
template:hit:<template_id>:<confidence>
strategy:structured
extract:template
runtime:llama.cpp.metal.v1:llm.schema.lite.v1:gguf_present=true:gguf_valid=true:gguf_metal_active
validate:grounding
confidence:orchestrated
identity_graph:<count>
memory:vector_index
```

## Overall Readiness

| Capability | Ready for TestFlight? | Notes |
|---|---:|---|
| GGUF model file downloaded/installed locally | Yes | Developer/simulator setup only. |
| GGUF manifest pinning | Yes | SHA and download URL present. |
| GGUF token inference | Yes | llama.cpp/Metal path is wired; real-device tuning remains. |
| LLM-only parser failure UX | Yes | Missing/invalid/generation failures return empty fields and user-visible notice. |
| Layout heuristic pairing | No | Intentionally disabled. |
| LayoutLM model pairing | No | Model selected and manifest-tracked; CoreML adapter/artifact still pending. |
| Utility/bank schema narrowing | No | Removed in favor of open vocabulary schema. |
| Review UI telemetry | Yes | DEBUG always, non-DEBUG when empty fields. |

## Recommendation

Short term:

1. Validate LLM parser failure UX in TestFlight when the GGUF artifact is missing or invalid.
2. Tune llama.cpp prompt/context settings with real scans.
3. Convert and bundle LayoutLMv3 CoreML for model-derived layout pairs.

Medium term:

1. Add the LayoutLMv3 token-classification adapter.
2. Promote diagnostics into golden tests for messy generic forms.

Long term:

1. Move from parser-only extraction to model ensemble extraction with deterministic validation.
2. Keep zero-egress guarantees by running all inference locally.
