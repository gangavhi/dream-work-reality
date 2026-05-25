# TrustNest — Document field identification investigation

**Product:** TrustNest (DreamWork iOS + Rust core)  
**Repo:** `/Users/bigdreams/dream-work-reality`  
**Investigation date:** 2026-05-25  
**App:** `apps/ios` — scheme `DreamWorkApp`, bundle `com.dream.nestledger.dev`

---

## Executive summary

Field identification **runs** end-to-end (OCR → pipeline → scan review → SQLite save), but **structured mapping is unreliable** for typical uploads because:

1. **No generative on-device model runs in production** — network LLM is hard-disabled; optional GGUF weights are not bundled; Rust `map_document_fields` and Swift layout heuristics do the work.
2. **Spatial label→value pairing mis-associates** OCR blocks (single-word values like `SHARMA` treated as labels), producing wrong canonical keys and junk extension fields.
3. **MRZ/barcode paths work** on passport samples with machine-readable zones; **layout-only documents** (bank statements, forms without MRZ) depend on fragile heuristics.

The failure mode users see is usually **wrong or nonsensical fields**, not a completely empty review screen — unless Settings has extraction off *and* layout pairs are empty *and* `UniversalDocumentParser` finds nothing.

---

## 1. Expected vs actual behavior

| Area | Expected | Actual (verified) |
|------|----------|-------------------|
| Document type | Open-vocabulary type with useful confidence | **Partially works** — `ClassificationAgent` + MRZ/keywords; US passport E2E → `Passport` |
| Field extraction | Context-aware mapping to `ProfileSchema` keys | **Unreliable** — wrong keys/values on passport E2E; simulated passport blocks produce `legal_last_name=Name`, `legal_middle_name=Date Of Birth Sharma Given` |
| On-device AI | Local model inference (ADR 0017) | **Not shipped** — `GenAIFieldMapper.fetchExtraction` always `nil`; `BundledModelStore.liteArtifactPath()` nil in test builds |
| Storage | Confirmed fields persist to profile | **Works** when user saves in `ScanReviewView` — `AppState.savePerson` → Rust `dreamwork_save_manual_entry_json` |
| Zero egress | No document OCR over internet | **Honored** — network LLM stubbed out |

---

## 2. End-to-end flow

```mermaid
flowchart TB
  IMG[Camera / gallery / PDF / laptop HTTP import]
  OCR[DocumentTextExtractor + Apple Vision OCR]
  SQLITE[(Rust: normalized doc JSON + extraction_run)]
  ORCH[DocumentIntelligenceOrchestrator]
  LAY[LayoutIntelligenceAgent — label|value pairs]
  OVF[OpenVocabularyFieldExtractor]
  MR[MachineReadableFieldExtractor — MRZ / PDF417]
  EXT[ExtractionAgent]
  ONDEV[OnDeviceFieldMapper — Rust FFI heuristics]
  GEN[GenAIFieldMapper — disabled returns nil]
  UNI[UniversalDocumentParser — regex fallback]
  CLS[ClassificationAgent]
  GND[OcrGroundingValidator]
  NFR[NameFieldReconciler]
  CONF[ConfidenceOrchestrator]
  ENRICH[CoreBridgeService.enrichScanReview]
  REV[ScanReviewView]
  SAVE[savePerson → SQLite profile]

  IMG --> OCR --> SQLITE
  OCR --> ORCH
  ORCH --> LAY --> OVF
  ORCH --> MR
  OVF --> EXT
  MR --> EXT
  EXT --> ONDEV
  EXT --> GEN
  GEN -.->|always nil| EXT
  EXT --> UNI
  EXT --> CLS
  CLS --> GND --> NFR --> CONF --> ENRICH --> REV --> SAVE
```

**Entry points:**

| Step | File |
|------|------|
| Import | `apps/ios/DreamWorkApp/Sources/Core/AppState.swift` — `importDocument(from:)` |
| OCR persist | `DocumentTextExtractor.extractAndPersist` → `ingestNormalizedDocumentJSON` |
| Enrichment | `apps/ios/DreamWorkApp/Sources/Core/CoreBridgeService.swift` — `enrichScanReview` |
| Pipeline | `DocumentIntelligencePipeline.extract` → `DocumentIntelligenceOrchestrator.process` |
| Review / save | `apps/ios/DreamWorkApp/Sources/Features/Scan/ScanReviewView.swift` — `saveFields()` |

---

## 3. Where it breaks

### 3.1 Failure classification

| Code | Symptom | Confirmed? |
|------|---------|------------|
| (a) Type never set | Review shows only “Other” | Rare on passport; keywords/MRZ help |
| (b) Type OK, wrong schema | Bank bill fields mapped to DL keys | Possible via `ProfileSchemaKeysForDocument` heuristics |
| (c) Extraction never called | Empty review | Only when all paths return `[]` |
| (d) Extraction returns empty | “No fields detected” | When OCR empty or all grounded away |
| **(e) Extraction returns wrong data** | **Fields present but incorrect** | **Yes — primary issue** |
| (f) Storage drops fields | Saved profile missing values | Not observed; save uses `editedValues` from suggestions |
| (g) UI doesn't bind | Fields not shown | Not observed when suggestions non-empty |

### 3.2 Breakpoint A — Network / generative extraction disabled

```78:84:apps/ios/DreamWorkApp/Sources/Core/GenAIFieldMapper.swift
    private static func fetchExtraction(
        layoutText: String,
        profileSchemaKeys: [String]
    ) async -> ExtractionResult? {
        // Network LLM extraction disabled — document data stays on-device (zero egress).
        nil
    }
```

`ExtractionAgent` never receives LLM JSON; there is no fallback call to the dead code path that posts to `/chat/completions`.

### 3.3 Breakpoint B — On-device mapper is heuristics-only (no GGUF inference)

```33:39:apps/ios/DreamWorkApp/Sources/Core/BundledModelStore.swift
    static func liteArtifactPath() -> String? {
        guard let manifest = manifest(),
              let artifact = manifest.artifacts.first(where: { $0.artifact_id == "llm.schema.lite.v1" })
        else { return nil }
        let path = modelsDirectory.appendingPathComponent(artifact.filename).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
```

Rust `map_document_fields` sets `engine: heuristic.on_device.v1` and only validates GGUF header if a file exists — **no llama.cpp inference** in the current tree (`local_document_mapper.rs`).

### 3.4 Breakpoint C — `ExtractionAgent` skips Rust mapper when provider is `.off`

```38:52:apps/ios/DreamWorkApp/Sources/Intelligence/Agents/ExtractionAgent.swift
        switch GenAISettings.provider {
        case .onDevice:
            if let mapped = OnDeviceFieldMapper.mapFields(
                layoutText: layout.modelInput,
                profileSchemaKeys: mapperKeys
            ) {
                suggestions = mergeSupplemental(primary: suggestions, supplemental: mapped.suggestions)
                openType = openType ?? mapped.documentType
                usedAI = true
            } else if suggestions.isEmpty {
                usedHeuristicFallback = true
            }
        case .off:
            break
        }
```

**Note:** `OpenVocabularyFieldExtractor` still runs before this switch, so “Off” is not fully off — users can still get (mis)mapped fields from layout pairs.

Default provider is **`.onDevice`** (not `.off`):

```25:38:apps/ios/DreamWorkApp/Sources/Core/GenAISettings.swift
    static var provider: Provider {
        get {
            guard let raw = UserDefaults.standard.string(forKey: providerKey) else {
                return .onDevice
            }
            // Legacy network providers — migrated to on-device (zero egress).
            if raw == ProviderLegacy.localLLM || raw == ProviderLegacy.cloudLLM {
                return .onDevice
            }
            guard let value = Provider(rawValue: raw) else { return .onDevice }
            return value
        }
```

### 3.5 Breakpoint D — Layout pairing treats values as labels

```207:209:apps/ios/DreamWorkApp/Sources/Core/OcrLayoutSerializer.swift
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count == 1, trimmed.count <= 24, trimmed.contains(where: { $0.isLetter }) {
            return true
        }
```

Any single token ≤24 letters (e.g. `SHARMA`, `PRIYA`) is classified as a **label**, so horizontal/vertical pairing attaches the wrong neighbor as its “value”. That flows into `OpenVocabularyFieldExtractor` → wrong `ProfileSchema` keys.

### 3.6 Breakpoint E — Junk extension fields from misparsed pairs

Rust `apply_label_value_pairs` and Swift open-vocabulary mapping create snake_case extension keys when labels do not resolve to canonical keys (e.g. `jane_marie`, `texas_u_s_a`, `united_states_of_america` on real passport E2E).

### 3.7 Storage / UI path (not broken)

`ScanReviewView.saveFields()` merges `editedValues` into `PersonRecord` and calls `appState.savePerson` — persistence works when the user confirms non-empty fields.

---

## 4. Root cause (confirmed)

**Primary:** Field identification depends on **heuristic layout pairing + regex Rust mapper**, not document-type-aware generative extraction. Pairing logic is **over-permissive** (`isFieldLabel`), so many scans map text to the **wrong profile keys** while still showing “High” confidence (especially MRZ-sourced rows).

**Secondary:** Product docs that cite `GenAISettings` default `.off` are **stale**; the app defaults to `.onDevice`, but that only enables the **same heuristic Rust path**, not a neural model.

**Tertiary:** `OcrGroundingValidator` does not catch semantically wrong assignments when the wrong value substring still appears somewhere in the OCR corpus (e.g. token `Name` in “Given Name(s)”).

---

## 5. Steps to reproduce (iOS Simulator)

### 5.1 Environment

- Xcode project: `apps/ios/DreamWorkApp.xcodeproj`
- Scheme: `DreamWorkApp`
- Simulator: iPhone 16 (OS 18.4) or iPhone 17 (OS 26.5)

### 5.2 Automated (recommended evidence)

```bash
cd /Users/bigdreams/dream-work-reality/apps/ios

# Core pipeline tests
xcodebuild -project DreamWorkApp.xcodeproj -scheme DreamWorkApp \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -derivedDataPath ./DerivedData-test \
  -only-testing:DreamWorkAppTests/DocumentIntelligencePipelineTests \
  -only-testing:DreamWorkAppTests/OnDeviceFieldMapperTests \
  -only-testing:DreamWorkAppTests/IntelligenceModuleTests \
  test

# Real US passport image → Vision OCR → full pipeline
xcodebuild -project DreamWorkApp.xcodeproj -scheme DreamWorkApp \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -derivedDataPath ./DerivedData-e2e \
  -only-testing:DreamWorkAppTests/PassportSamplePipelineE2ETests \
  test
```

Fixture: test bundle resource `sample-document.png` (copy of `demo/sample-documents/us-passport-sample.png`).

### 5.3 Manual simulator

```bash
cd /Users/bigdreams/dream-work-reality
./scripts/prepare_simulator_testing.sh "iPhone 17"
./scripts/load_sample_passport_to_simulator.sh "" "iPhone 17"
```

In app: **Home → Browse laptop documents →** pick `us-passport-sample.png` from `http://127.0.0.1:8010/` → **Review scan** → inspect fields → **Save**.

**Blocker note:** If `demo/sample-documents/` has no PNG, laptop import and Photos load steps fail; unit/E2E tests still run via bundled fixture.

---

## 6. Evidence and logs

### 6.1 Unit tests (2026-05-25)

```
** TEST SUCCEEDED **
DreamWorkAppTests: DocumentIntelligencePipelineTests, OnDeviceFieldMapperTests,
IntelligenceModuleTests (8 tests, DerivedData-test)
```

`testExtractUsesUniversalParserWhenLLMOff` — with `GenAISettings.provider = .off`, SSN regex path still yields `ProfileFieldKey.ssn` from universal parser.

### 6.2 Simulated passport blocks (diagnostic)

Pipeline trace (onDevice and off both show layout-driven extraction):

```
trace=["ocr:vision.en.v1", "layout:layout.heuristic.v1", "extract:on_device",
       "classify:heuristic.on_device.v1", "validate:grounding", "confidence:orchestrated",
       "memory:vector_index"]
```

**Wrong fields (representative):**

```
legal_first_name=Priya
legal_middle_name=Date Of Birth Sharma Given
legal_last_name=Name
date_of_birth=15/03/1990
passport_number=Z1234567
republic_of_india=PASSPORT
sharma=PRIYA
```

### 6.3 Real image E2E — `PassportSamplePipelineE2ETests` (2026-05-25)

```
=== Passport E2E pipeline trace ===
ocr:vision.en.v1 → layout:layout.heuristic.v1 → extract:on_device → classify:heuristic.on_device.v1
  → validate:grounding → confidence:orchestrated → memory:vector_index

displayType=Passport openLabel=Passport
usedAI=true heuristicFallback=false machineReadable=true
suggestionCount=16

  display_name=Jane Marie Smith        conf=High  src=mrz
  legal_first_name=Jane                conf=High  src=mrz
  legal_middle_name=Marie              conf=High  src=mrz
  legal_last_name=Smith                conf=High  src=mrz
  date_of_birth=03/15/1985             conf=High  src=mrz
  passport_number=123456789            conf=High  src=mrz
  passport_country=United States of America  conf=High  src=mrz
  passport_expiry=01/09/2030           conf=High  src=mrz

  city=Texas, U.s.a. Date Of Issue     conf=High  src=mrz      ← wrong key/value
  drivers_license_issue_date=10 JAN 2020  conf=High  src=onDevice  ← wrong schema
  tax_form_type=P                      conf=High  src=onDevice  ← junk extension
  jane_marie=15 MAR 1985               conf=High  src=onDevice
  texas_u_s_a=10 JAN 2020              conf=High  src=onDevice
  united_states_of_america=P           conf=High  src=onDevice
```

**Interpretation:** MRZ decoding is strong for core identity fields; **layout/heuristic layers pollute** the suggestion list with incorrect canonical and extension fields. Users must manually delete bad rows — matches “field identification not working” in practice.

### 6.4 Simulator launch

`prepare_simulator_testing.sh` starts HTTP servers on ports **8010** (sample docs) and **8009** (Downloads), boots simulator, builds and launches `com.dream.nestledger.dev`. Use device name matching an installed runtime (e.g. `iPhone 17`).

---

## 7. Recommended fixes (actionable)

| Priority | Fix | Rationale |
|----------|-----|-----------|
| **P0** | Tighten `isFieldLabel` — require known label phrases or trailing `:`; **never** treat bare proper-noun tokens as labels | Stops SHARMA/PRIYA mis-pairing (Breakpoint D) |
| **P0** | Filter extension keys in `ExtractionAgent` / `ScanFieldValidator` unless label resolved via `SemanticFieldLabelMapper` | Removes `jane_marie`, `texas_u_s_a` noise on passport E2E |
| **P1** | Ship bundled GGUF + wire `GenerativeLlmSession` in `local_document_mapper.rs` | Delivers ADR 0017; replaces regex-only “on-device AI” |
| **P1** | When `GenAISettings.provider == .off`, skip `OpenVocabularyFieldExtractor` or show explicit “heuristics only” empty state | Makes “Off” truthful |
| **P2** | LayoutLM / improved pairing artifact (`ModelArtifactSlot.layoutLM`) | Better label|value on unstructured scans |
| **P2** | Review UI: flag `mappingSource == .onDevice` rows that fail plausibility checks (date in `city`, DL key on passport) | Reduces false “High” trust |

---

## Related documentation

- [trustnest-ml-storage-planner.md](trustnest-ml-storage-planner.md) — ML SQLite table fit, DDL, and removed post-processing stages
- [trustnest-document-classifier-huggingface-analysis.md](trustnest-document-classifier-huggingface-analysis.md) — document **type** gap (Qwen prompt vs RVL-CDIP / visual classifiers) and HF model fit
- [field-mapping-accuracy-analysis.md](field-mapping-accuracy-analysis.md) — partially stale on `GenAISettings` default
- [trustnest-zero-egress-design-constraint.md](trustnest-zero-egress-design-constraint.md)
- [project-requirements-and-implementation-gap.md](project-requirements-and-implementation-gap.md)
- `scripts/prepare_simulator_testing.sh`, `apps/ios/PUBLISHING.md`
