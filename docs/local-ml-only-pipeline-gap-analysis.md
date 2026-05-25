# Local ML-Only Pipeline Gap Analysis

**Date:** 2026-05-25  
**Question:** Is the current code fully powered by local ML models, with no rudimentary fallback, for:

1. Document type identification.
2. Field/data parsing.
3. SQLite schema/table matching or new-table need identification.

## Executive Summary

> Implementation update: the gaps below have now been addressed in code. `ClassificationAgent` calls
> `dreamwork_classify_document_json` instead of machine-readable or keyword decisions, `ExtractionAgent`
> only calls the local LLM parser, and `storage_routing.rs` now fails closed unless a local GGUF storage
> planner returns a plan. The sections below remain as the evidence trail for why these corrections were
> required.

| Capability | Pre-Fix Status | Complete? | Bottom Line |
|---|---|---:|---|
| Document type identification | Heuristic/rules-first | No | `ClassificationAgent` does not call a local ML classifier. It labels the engine as `llm.schema.lite.v1` when a model is installed, but the actual decision still comes from machine-readable source checks and keyword inference. |
| Field/data parsing | Mixed; LLM mapper exists but pipeline still has non-ML sources | Partial | `local_document_mapper.rs` is now LLM-only and fail-visible, but the Swift pipeline still runs deterministic template extraction, machine-readable extraction, and learned corrections before/around the LLM parser. |
| SQLite schema/table routing | Rules-only | No | `storage_routing.rs` explicitly builds a rules-only plan from canonical key membership. It does not inspect SQLite schema/table existence with a local ML model and does not decide when a new schema table is needed. |

## 1. Document Type Identification

### Current Code Path

Entry point:

- `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/DocumentIntelligenceOrchestrator.swift`

The orchestrator calls:

```swift
let classification = ClassificationAgent.classify(
    modelInput: layout.modelInput,
    mappedDocumentType: nil,
    machineReadableSources: machineReadable.sources
)
```

Classifier implementation:

- `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/ClassificationAgent.swift`

Current classification logic is not ML inference. It uses:

- `machineReadableSources.contains("pdf417")`
- `machineReadableSources.contains("drivers_license")`
- `machineReadableSources.contains("passport")`
- `ProfileSchemaKeysForDocument.inferOpenType(from:)`, which checks keywords such as `AADHAAR`, `PASSPORT`, `VISA`, `BANK STATEMENT`, and `UTILITY`.

Evidence:

```swift
if openType == nil {
    openType = ProfileSchemaKeysForDocument.inferOpenType(from: modelInput)
    if openType == "other" { openType = nil }
}
```

The model registry is only used to choose an `engineID`:

```swift
switch ModelArtifactRegistry.loadState(for: .documentClassifier) {
case .installed: return ModelArtifactSlot.documentClassifier.rawValue
case .heuristicFallback: return "heuristic.on_device.v1"
default: return "heuristic.on_device.v1"
}
```

This is a reporting/status decision, not a model inference call.

### Gap

Document type identification is **not actively powered by a local ML model**.

Even if the GGUF artifact is installed, `ClassificationAgent` does not call:

- `OnDeviceFieldMapper`
- `local_document_mapper.rs`
- `LlamaCppBridge.mm`
- any CoreML classifier

It also does not fail if the classifier model is unavailable. It simply continues with heuristic classification.

### Required Correction

Replace `ClassificationAgent.classify(...)` with a local model-backed classifier path:

1. Add a dedicated local classification call, likely using the same GGUF/llama.cpp runtime or a smaller CoreML classifier.
2. Require JSON output such as:

   ```json
   {
     "document_type": "bank_statement",
     "confidence": 0.93,
     "reason": "OCR contains statement period and account summary"
   }
   ```

3. Return a fail-visible status when local classifier inference fails.
4. Remove keyword-based classification as an automatic fallback.
5. Keep machine-readable payloads as evidence only if product explicitly allows them as non-ML trusted sources; otherwise they should not determine document type.

## 2. Field/Data Parsing

### Current Code Path

Primary orchestrator:

- `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/ExtractionAgent.swift`

The local LLM mapper path is present:

- `apps/ios/DreamWorkApp/Sources/Core/OnDeviceFieldMapper.swift`
- `core/dreamwork_core/src/local_document_mapper.rs`
- `core/dreamwork_core/src/inference/llama_cpp.rs`
- `apps/ios/DreamWorkApp/Sources/Native/LlamaCppBridge.mm`

The Rust mapper is now stricter than before:

```rust
if !gguf_present {
    return failed_response(..., LLM_PARSER_MISSING.to_string(), ...);
}
if !gguf_valid {
    return failed_response(..., LLM_PARSER_INVALID.to_string(), ...);
}
```

And it calls llama.cpp for schema JSON:

```rust
match run_llama_schema_plan(req) {
    Ok(plan) => { /* apply LLM fields */ }
    Err(err) => failed_response(...)
}
```

This part is aligned with the local-ML-only requirement.

### Remaining Non-ML Parsing Sources

The Swift extraction pipeline still allows several non-ML field sources.

#### Template Extraction

`ExtractionAgent` runs template extraction before the LLM mapper:

```swift
if strategy.structure == .structured, let templateMatch {
    suggestions = DocumentTemplateAgent.extract(layout: layout, match: templateMatch)
    usedTemplateExtractor = !suggestions.isEmpty
}
```

Files:

- `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/DocumentTemplateAgent.swift`
- `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/ExtractionAgent.swift`

This is deterministic coordinate/rule extraction, not local ML.

#### Machine-Readable Extraction

`ExtractionAgent` also merges machine-readable fields:

```swift
let machineReadable = MachineReadableFieldExtractor.extract(
    from: payloadHints,
    plainOCRText: layout.layoutText
)
suggestions = mergeSupplemental(primary: machineReadable.suggestions, supplemental: suggestions)
```

File:

- `apps/ios/DreamWorkApp/Sources/Core/MachineReadableFieldExtractor.swift`

This is barcode/MRZ/parser logic, not local ML.

#### Learned Corrections

`ExtractionAgent` applies learned suggestions:

```swift
let learned = IncrementalLearningStore.learnedSuggestions(...)
if !learned.isEmpty {
    suggestions = mergeSupplemental(primary: suggestions, supplemental: learned)
}
```

File:

- `apps/ios/DreamWorkApp/Sources/Intelligence/Learning/IncrementalLearningStore.swift`

This is user-correction replay, not local ML inference.

#### Provider Off Switch

`ExtractionAgent` still respects:

```swift
switch GenAISettings.provider {
case .onDevice:
    ...
case .off:
    break
}
```

If local ML is mandatory, `provider = .off` should not allow the document parsing pipeline to proceed as if parsing could be complete.

### Gap

Field/data parsing is **partially implemented**.

The Rust `local_document_mapper.rs` path is local-LLM-only, but the app-level field parsing pipeline is not. It can still produce field suggestions from:

- templates
- barcode/MRZ/machine-readable payloads
- learned corrections

These may be useful product features, but they violate the strict interpretation of “each has to be powered by local ML model and there should not be fallback mechanism which is rudimentary.”

### Required Correction

If the requirement is strict:

1. Make `ExtractionAgent` call the LLM parser first and treat it as the only field/data parser.
2. Remove or gate `DocumentTemplateAgent.extract(...)` from the production parsing path.
3. Remove or gate `MachineReadableFieldExtractor.extract(...)` from field suggestion generation; optionally pass decoded payload text into the LLM as evidence.
4. Remove learned correction auto-application from parsing; optionally pass corrections as context to the LLM.
5. Remove or disable `GenAISettings.provider = .off` for document parsing.
6. Make scan review show a blocking parser failure when the LLM model is missing or generation fails.

## 3. SQLite Schema/Table Matching And New Table Detection

### Current Code Path

Swift caller:

- `apps/ios/DreamWorkApp/Sources/Core/CoreBridgeService.swift`
- `apps/ios/DreamWorkApp/Sources/Core/CoreIngestFFI.swift`

Rust FFI:

- `core/dreamwork_core/src/ffi.rs`

```rust
pub extern "C" fn dreamwork_plan_storage_json(ptr: *const c_char) -> *mut c_char {
    ...
    match crate::ingest::plan_storage_from_json(&s) {
```

Rust ingest wrapper:

- `core/dreamwork_core/src/ingest.rs`

```rust
Ok(crate::storage_routing::plan_storage(&PlanStorageRequest {
    fields: req.fields,
    person_id: req.person_id,
    profile_schema_keys: req.profile_schema_keys,
}))
```

Routing implementation:

- `core/dreamwork_core/src/storage_routing.rs`

The file documents itself as rules-only:

```rust
//! Stage 2 rules-only storage routing: map extracted fields to `manual_field` vs extension keys.
```

The actual routing logic checks membership in canonical keys:

```rust
let is_canonical = canonical_set.contains(&key) || is_canonical_profile_key(&key);
let (op, reason) = if is_canonical {
    (StorageOperationKind::UpsertManualField, "canonical_profile_key".to_string())
} else {
    (StorageOperationKind::UpsertExtensionField, "extension_field".to_string())
};
```

### SQLite Schema Evidence

Rust core schema:

- `core/dreamwork_core/src/db/migrate.rs`

Core Rust tables are fixed migrations:

```sql
CREATE TABLE IF NOT EXISTS manual_entry (...);
CREATE TABLE IF NOT EXISTS manual_field (...);
CREATE TABLE IF NOT EXISTS extraction_run (...);
```

iOS people database schema:

- `apps/ios/DreamWorkApp/Sources/Features/People/PeopleSQLiteStore.swift`

Swift creates fixed tables:

- `people`
- `driver_licenses`
- `family_members`
- `emergency_contacts`
- `documents`
- `genai_fields`

There is no local ML model inspecting schema metadata and deciding:

- which existing table best matches a parsed document
- whether a new table should be proposed
- what columns a new table should contain
- whether a migration is required

### Gap

SQLite schema/table routing is **not powered by local ML**.

It is rules-only and key-set based. It also does not truly route to typed tables. Unknown/document-specific values are still modeled as extension fields rather than a new schema/table recommendation.

### Required Correction

Add a local model-backed storage planner:

1. Gather SQLite schema metadata locally:

   ```sql
   SELECT name, sql FROM sqlite_master WHERE type = 'table';
   PRAGMA table_info(<table>);
   ```

2. Send extracted fields + document type + schema metadata to a local LLM prompt.
3. Require constrained JSON output:

   ```json
   {
     "storage_decision": "use_existing_table",
     "target_table": "documents",
     "field_mapping": {
       "passport_number": "number",
       "passport_expiry": "expiry_mmddyyyy"
     },
     "new_table_required": false,
     "new_table_proposal": null,
     "confidence": 0.91
   }
   ```

4. If a new table is required, produce a migration proposal, not execute it automatically:

   ```json
   {
     "storage_decision": "propose_new_table",
     "new_table_required": true,
     "new_table_proposal": {
       "table_name": "bank_statements",
       "columns": [
         {"name": "person_id", "type": "TEXT"},
         {"name": "account_number", "type": "TEXT"},
         {"name": "statement_period", "type": "TEXT"}
       ]
     }
   }
   ```

5. Fail visibly when local storage-planner inference fails.
6. Remove `canonical_profile_key` / `extension_field` as the final routing decision, or keep it only as model input context.

## Overall Readiness

| Requirement | Current Grade |
|---|---|
| Local ML document type identification | Not complete |
| Local ML field/data parsing | Partially complete |
| Local ML SQLite schema/table matching | Not complete |
| No rudimentary fallback | Not complete |

## Highest Priority Gaps

1. `ClassificationAgent` needs a real local model call. Today it is keyword/machine-readable based.
2. `ExtractionAgent` still accepts non-ML field sources before/around the LLM mapper.
3. `storage_routing.rs` is explicitly rules-only and does not inspect SQLite schema with ML.
4. The local model artifact state is not yet strict across all three subsystems. Field parsing is strict in Rust, but classification and storage routing still continue without local ML.

## Recommended Implementation Order

1. Add a local LLM-powered `DocumentClassificationAgent` using the existing llama.cpp bridge.
2. Make `ExtractionAgent` LLM-only for field suggestions; pass templates/barcodes/learned corrections as prompt context only.
3. Add a Rust local LLM storage planner that receives SQLite schema metadata and emits constrained storage-decision JSON.
4. Add telemetry for all three model stages:
   - `classify:llm.schema.lite.v1:<status>`
   - `parse:llama.cpp.metal.v1:<status>`
   - `storage_plan:llama.cpp.metal.v1:<status>`
5. Add fail-visible scan review messages for each failed local model stage.

