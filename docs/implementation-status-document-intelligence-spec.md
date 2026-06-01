# Document intelligence platform — implementation status

**Product:** DreamWork / TrustNest (iOS)  
**Spec:** Fully local, zero-egress, automatic post-scan extraction (June 2026)  
**Repo baseline:** `ganga-2026-05-16-2` @ `4d5b351` (marketing **1.1.0**, build **50** in `project.yml`; TestFlight IPA may be **51**)  
**Audience:** Product, QA, engineering  

---

## Executive summary

| Area | Status | Notes |
|------|--------|--------|
| Zero-egress / local-only | **Mostly met** | No cloud LLM; OCR and models on device. DEBUG-only localhost core-api sync. |
| Automatic OCR after scan | **Met** | Camera, images, PDF (≤25 pages). |
| Automatic classification | **Partial** | MRZ/barcode/keywords + optional GGUF; not a dedicated trained classifier for all types. |
| Automatic field mapping | **Partial** | ONNX MiniLM + layout pairs + MRZ/barcode; GGUF often deferred or manual on iPhone. |
| **All relevant fields** | **Not met** | Address/city/state/ZIP often work; many DL/passport/insurance fields missing or wrong. |
| No manual “Extract” button | **Not met** | “Run full on-device extraction” always shown when on-device AI is enabled. |
| Automatic profile save | **Not met** | User must tap **Save** on review screen. |
| macOS app | **Not in scope** | iOS 17+ only today. |
| PaddleOCR fallback | **Stub only** | Slot exists; no wired model. |

**Bottom line:** The **pipeline architecture** for your spec exists (orchestrator, router, validation, confidence, standardized JSON). The **product behavior** still differs: incomplete field coverage, optional/heavy LLM gating, manual extraction affordance, and manual profile commit.

---

## Required user flow vs actual flow

### Required (spec)

```text
Scan → OCR → Classify → Map → Validate → Normalize → Profile → Review UI
(all automatic, no extra extraction tap)
```

### Actual (code: `AppState.presentScanReview`, `CoreBridgeService.enrichScanReview`)

```text
Scan / import
  → DocumentTextExtractor (Vision OCR, persist to SQLite extraction_run)
  → presentScanReview
       → enrichScanReview(runOnDeviceLLM: false)   // ONNX/layout/MRZ/barcode; NO GGUF
       → Review UI opens with first-pass fields
       → IF on-device provider AND memory headroom:
            runOnDeviceExtractionForCurrentScan()  // enrichScanReview(runOnDeviceLLM: true)
       → ELSE: user sees “Run full on-device extraction” button
  → User taps Save → profile written to Rust/SQLite
```

**Gaps vs spec:**

1. **Two-phase extraction** — heavy Qwen GGUF may not run on first paint (memory guard).
2. **Manual button** — `OnDeviceMLPolicy.requiresManualExtractionTrigger` is always `true` for on-device provider; `ScanReviewView` always shows the section.
3. **Profile not auto-created** — structured fields are suggestions until **Save**.

---

## Pipeline architecture (implemented)

Single entry: `DocumentIntelligenceOrchestrator.process` → used by `DocumentIntelligencePipeline` and `DocumentUnderstandingService`.

| Stage | Component | Implemented? |
|-------|-----------|--------------|
| OCR ingest | `DocumentTextExtractor`, `VisionOcrAdapter`, `OcrEngine` | Yes |
| MRZ / barcode | `EmbeddedPayloadHints`, `MachineReadableFieldExtractor` | Yes |
| Layout pairs | `LayoutIntelligenceAgent` (LayoutLM CoreML if installed, else `OcrLayoutSerializer` heuristics) | Yes |
| Classification | `LocalDocumentClassifier` (MRZ, PDF417, keywords, optional `ClassificationAgent` GGUF) | Partial |
| Routing | `ExtractionStrategyAgent` + `DocumentExtractionRouter` (known fast vs unknown semantic) | Yes |
| Extraction | `ExtractionAgent` (ONNX `OpenVocabularyFieldExtractor`, MRZ, GGUF `OnDeviceFieldMapper`, heuristics) | Partial |
| Validation | `DocumentValidationPipeline`, `ScanFieldValidator`, `MappedFieldValueValidator`, `OcrGroundingValidator` | Yes |
| Address merge | `AddressFieldMerger` | Yes |
| Normalization | `FieldNormalizationEngine` | Yes |
| Confidence | `ConfidenceOrchestrator` (OCR + semantic + validation + grounding composite) | Yes |
| Standardized JSON | `SchemaMappingEngine.StandardizedDocumentOutput` | Yes |
| Person match hint | `CoreIngestFFI.resolvePerson` on enrichment | Yes |
| Storage planner | `CoreIngestFFI.planStorage` — **deferred** during scan review | Deferred |
| Fraud agent | `FraudDetectionAgent` | Disabled in trace (`fraud:disabled_ml_only_pipeline`) |

**Routing (spec: avoid running all models):** Implemented. Known path uses MRZ/barcode/ONNX first; unknown path may add layout-AI chunks + GGUF when `allowHeavyLLM` and memory allow.

---

## OCR (spec vs implementation)

| Requirement | Status | Implementation |
|-------------|--------|----------------|
| Apple Vision (primary) | **Yes** | `OcrEngine`, `VisionOcrAdapter` — blocks, confidence, bounds |
| Core Image preprocessing | **Yes** | Contrast/sharpen passes, address-region crops in `OcrEngine` |
| PDF / images / multi-page | **Yes** | `DocumentTextExtractor` (max 25 PDF pages) |
| Camera scan | **Yes** | `DocumentCameraView`, `HomeView` |
| PaddleOCR fallback | **No** | `PaddleOcrAdapter` — `isAvailable` false until artifact installed; returns `nil` |
| Barcode detection | **Yes** | Vision barcode on rasterized pages |
| MRZ detection | **Yes** | Line heuristics on OCR text + MRZ-driven passport hints |
| Raw OCR in UI | **Yes** | `ScanReviewView` — reading order, numbered blocks, label→value pairs |
| Per-block confidence in UI | **Partial** | Stored on blocks; review UI does not list per-block scores |

---

## Document classification (spec vs implementation)

| Document type (spec) | Detection today |
|----------------------|-----------------|
| Driver license | Barcode, keywords, layout; Texas parser **not** in main `ExtractionAgent` path |
| Passport | MRZ, keywords, `IndianPassportParser` via MR/OCR hints |
| Insurance card | Keywords + registry; **limited** field schema |
| Identity / state ID | Registry + keywords |
| Utility bill | Keywords + schema keys |
| Medical | Keywords + minimal schema |
| Unknown | Routed to `unknownSemantic` → ONNX + optional GGUF |

**Not met:** Dedicated local VLM/classifier for every type; `DocumentTemplateAgent` disabled (`template:disabled:ml_only`).

---

## Field mapping & coverage

### What works reasonably well today

- Address line, city, state, postal code (when layout pairs are correct)
- Some DL/passport fields when MRZ or PDF417 barcode is present
- MiniLM ONNX label→profile_key mapping when label/value pairs are clean
- Post-mapping validation (future DOB, issue/expiry order, grounding, shape rules)

### Known failure modes (documented May 2026)

See [field-mapping-root-cause-2026-05-30.md](./field-mapping-root-cause-2026-05-30.md):

- Spatial pairing can swap names ↔ addresses (mitigated in `OcrLayoutSerializer`, needs TestFlight verification)
- ONNX maps wrong when pairs are wrong
- Heuristic fallback is shallow (`UniversalDocumentParser`)

### Spec field checklist — driver license

| Field | In `ProfileSchema` / extraction path? | Typical capture |
|-------|--------------------------------------|-----------------|
| First / middle / last name | First/last yes; middle **no dedicated key** | Partial |
| DOB | Yes | Partial |
| Address, city, state, ZIP | Yes | Often yes |
| License number | Yes | Partial |
| Issue / expiration | Yes | Partial |
| Class, restrictions, endorsements | **Not in schema keys** for DL | **No** |

### Passport (spec)

| Field | Status |
|-------|--------|
| Name, DOB, passport #, nationality, country, dates, gender | Keys exist; capture **partial** (MRZ helps) |
| Address on passport | Optional; **weak** |
| MRZ values | Extracted via `MachineReadableFieldExtractor` when detected |

### Insurance card (spec)

| Field | Status |
|-------|--------|
| Member ID, carrier, subscriber name | Partial (`insuranceMemberId`, etc.) |
| Group ID, policy #, RxBIN, RxPCN, effective dates | **Missing or not mapped** |

### “Do not stop after a few fields”

**Not met.** Extraction merges sources but has no “exhaustive document sweep”; early paths can return after ONNX + few pairs. No guarantee all schema keys are attempted.

---

## Validation layer (spec vs implementation)

| Validation | Status |
|------------|--------|
| Dates (future DOB, issue after expiry) | Yes — `DocumentValidationPipeline` |
| ID / passport plausibility | Partial |
| State codes | Via `ScanFieldValidator` / `MappedFieldValueValidator` |
| Address consistency | `AddressFieldMerger` |
| OCR grounding | `OcrGroundingValidator` |
| Reject impossible mappings | Yes — keys dropped with trace warnings |

---

## Confidence (spec vs implementation)

| Requirement | Status |
|-------------|--------|
| OCR confidence | Used as block average in `ConfidenceOrchestrator` |
| Mapping confidence | From `mappingSource` + semantic score |
| Validation confidence | Binary pass/fail in orchestrator |
| Final composite per field | `confidenceScore` on `OcrFieldSuggestion` |
| UI shows all scores | **Partial** — low-confidence / “Review required” caption; no per-signal breakdown in UI |

---

## Review UI (spec vs implementation)

| Section | Status |
|---------|--------|
| Structured fields (editable) | **Yes** — grouped by `ProfileSchema` |
| Raw OCR output | **Yes** — disclosure with pairs, lines, blocks |
| Confidence indicators | **Partial** — flags, not full score grid |
| Editable corrections | **Yes** |
| Compare field ↔ source OCR | **Partial** — user compares manually via OCR section |
| Pipeline telemetry | DEBUG or empty suggestions only |

---

## Zero-egress & performance

| Requirement | Status |
|-------------|--------|
| No network for document AI | **Yes** — `GenAISettings` on-device only; `ZeroEgressPolicy.allowsLLMEndpoint` false |
| Local models in Release IPA | Qwen 0.5B GGUF, MiniLM ONNX, optional LayoutLM CoreML |
| Minimize latency | Router avoids always loading GGUF; tradeoff: fewer fields |
| iPhone memory (jetsam) | `OnDeviceMemoryGuard` defers/skips heavy LLM; historical TestFlight crashes drove manual policy |

---

## Legacy / parallel code paths (not main scan pipeline)

These exist but are **not** wired through `DocumentIntelligenceOrchestrator` for Home → scan review:

- `TexasDriverLicenseParser`, `DriverLicenseFieldMapper` — used in **Forms** `DriverLicenseScanner` and tests
- `OcrFieldSuggester` — older suggester path
- `GenAIFieldMapper` / HTTP client types — zero-egress blocks cloud use

---

## Standardized JSON output (spec example)

Produced internally as `SchemaMappingEngine.StandardizedDocumentOutput` (not shown as raw JSON in review UI):

- Keys vary by `document_type` (e.g. DL: `first_name`, `last_name`, `dob`, `license_number`, …)
- Empty keys included with `confidence: 0` when missing
- `fieldsRequiringReview` populated from confidence threshold

Example shape matches spec intent; **field completeness** does not.

---

## Success criteria scorecard

| Criterion | Met? |
|-----------|------|
| OCR completes automatically after scan | **Yes** |
| Mapping starts automatically (any pass) | **Yes** (ONNX/layout); full GGUF **conditional** |
| All relevant fields extracted | **No** |
| Structured profile generated automatically | **No** (suggestions only until Save) |
| Raw OCR shown automatically | **Yes** |
| User never presses extra extraction button | **No** |
| Fully local, zero egress | **Yes** (product path) |

---

## Recommended implementation order (to close spec gap)

1. **Remove or hide manual extraction** when first-pass pipeline already ran ONNX + validation (keep only for low-memory retry).
2. **Wire specialized parsers** (`TexasDriverLicenseParser`, `DriverLicenseFieldMapper`, `IndianPassportParser`) into `ExtractionAgent` known-fast path before generic ONNX.
3. **Expand schemas** — DL class/restrictions/endorsements; insurance RxBIN/RxPCN/group/policy dates.
4. **Exhaustive field sweep** — iterate all `ProfileSchemaKeysForDocument.keys` and layout pairs; do not exit early on `suggestions.count >= 2`.
5. **Enable PaddleOCR** or improve Vision fallback when average block confidence &lt; threshold.
6. **Review UI** — per-field confidence breakdown + highlight source OCR span.
7. **Optional:** auto-save draft profile after extraction (spec “profile generation”) with explicit user confirm for merge.
8. **macOS** — separate target if still required.

---

## Key source files

| Area | Path |
|------|------|
| Scan → review flow | `apps/ios/DreamWorkApp/Sources/Core/AppState.swift` |
| Enrichment / pipeline | `apps/ios/DreamWorkApp/Sources/Core/CoreBridgeService.swift` |
| Orchestrator | `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/DocumentIntelligenceOrchestrator.swift` |
| Extraction | `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/ExtractionAgent.swift` |
| Routing | `apps/ios/DreamWorkApp/Sources/Intelligence/Routing/DocumentExtractionRouter.swift` |
| OCR | `apps/ios/DreamWorkApp/Sources/Core/OcrEngine.swift`, `DocumentTextExtractor.swift` |
| Review UI | `apps/ios/DreamWorkApp/Sources/Features/Scan/ScanReviewView.swift` |
| ML policy | `apps/ios/DreamWorkApp/Sources/Native/OnDeviceMLPolicy.swift` |
| Zero egress | `apps/ios/DreamWorkApp/Sources/Core/ZeroEgressPolicy.swift` |

---

*Generated against the June 2026 document intelligence platform specification and codebase at `4d5b351`.*
