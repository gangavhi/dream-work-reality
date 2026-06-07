# Standalone on-device models (TrustNest rewrite v2)

Testing iterations on DL, US passport, Indian passport, and SSN produce a **golden corpus** (`apps/ios/DreamWorkAppTests/Fixtures/manifest.json`). Each model below is **standalone**: own artifact, own I/O contract, no dependency on other models or the legacy Intelligence orchestrator.

## Design rules

1. **Standalone** — One `.mlmodel` / `.mlpackage` per job. Versioned id (`trustnest.doc-type.v1`). Shippable or omitted independently.
2. **Hint-only** — Models never replace parsers. Output merges via `MachineReadableFieldExtractor.mergeTrusted` (same pattern as PDF417 / MRZ).
3. **Heuristic fallback** — If artifact missing or confidence low, existing rules run unchanged (DL path in build 56 stays default).
4. **Synthetic training in repo** — Manifest + test fixtures only. Real scans train locally; never commit.
5. **No orchestrator** — `RewritePipeline` calls thin adapters; no `DocumentIntelligenceOrchestrator`, no default ONNX/GGUF.

```
Capture → OCR (Vision) → [optional standalone model] → Parser (truth) → Review
                              ↓ hint only
                         mergeTrusted
```

---

## Fixture manifest schema

Path: `apps/ios/DreamWorkAppTests/Fixtures/manifest.json`

| Field | Purpose |
|-------|---------|
| `id` | Stable corpus id |
| `documentType` | Layer A type |
| `source` | `synthetic` \| `photo_local_only` |
| `testBinding` | XCTest that proves the fixture |
| `expectedFields` | profile_key → value |
| `rejectedFields` | profile_key → values that must **not** appear |
| `failureModes` | Tags for model training slices |
| `photoFixture` | Path under `demo/sample-documents/household-fixtures/` when added |

**Workflow:** Every parser bugfix → add/update manifest row + XCTest → tag `failureModes` → re-export training rows when a model is ready.

---

## Priority standalone models (3)

### 1. `trustnest.doc-type.v1` — Document type classifier

**Problem:** SSN scans classified as `unknown` (build 56); extraction skipped. Must cover **all scannable must-have categories** in the feature list.

| Must-have category | Create ML labels |
|--------------------|------------------|
| Passport / ID | `passport`, `stateId` |
| Driver License | `driversLicense` |
| SSN Card | `ssnCard` |
| Address Proof | `utilityBill` |
| Insurance Card | `insuranceCard` |
| W-2 / 1099 / Pay stub | `w2`, `form1099`, `payStub` |
| Bank Statement | `bankStatement` |
| Emergency Contact / Employment | manual only — no classifier row |

| | |
|--|--|
| **Input** | OCR text snippet (first ~2 KB) or bag-of-signals |
| **Output** | `document_type` + `confidence` |
| **Trained on** | All manifest fixtures + local `labels.jsonl` after device tests |
| **Runtime** | Core ML text classifier (Create ML) or NLModel |
| **Integration** | `RewritePipeline` step 3: if heuristic confidence &lt; 0.85, call model; else keep heuristic |
| **Standalone** | No passport/DL parsers; no other models |

```swift
// Future adapter surface (illustrative)
enum StandaloneDocumentTypeClassifier {
    static func classify(ocrText: String) -> DocumentClassification? // nil → use heuristic
}
```

---

### 2. `trustnest.passport-page.v1` — Passport biodata page ranker

**Problem:** Multi-page PDF merges biodata + back page + noise; MRZ/parser drown in garbage (Indian passport tests).

| | |
|--|--|
| **Input** | Per-page features (no raw image required): `mrz_line_count`, `noise_ratio`, `has_surname`, `has_pin`, `line_count` |
| **Output** | `biodata_page_index` + `confidence` |
| **Trained on** | Fixtures tagged `multi_page_noise`, `ocr_noise_address` |
| **Runtime** | Small Core ML regressor/classifier (tabular — cheap on device) |
| **Integration** | Before `PassportParser` / `IndianPassportParser`: OCR only selected page(s) |
| **Standalone** | Does not call doc-type or field-label models |

```swift
enum StandalonePassportPageRanker {
    struct PageFeatures { /* counts derived from OCR blocks */ }
    static func rank(pages: [PageFeatures]) -> Int? // nil → use all pages (current behavior)
}
```

---

### 3. `trustnest.field-label.v1` — Field label → profile key mapper

**Problem:** Layout label→value pairs map `Given Names` → first name, `Place of Birth` → city (passport); DL avoids this via numbered fields + barcode.

| | |
|--|--|
| **Input** | `(document_type, label, value)` |
| **Output** | `profile_key` + `confidence` (or `null` = unknown) |
| **Trained on** | Positive pairs from clean fixtures; negatives from `rejectedFields` in manifest |
| **Runtime** | Core ML text classifier **or** embedding cosine (MiniLM) in a **separate** bundle |
| **Integration** | Optional hints into `RewriteFieldExtractor`; parser wins on conflict |
| **Standalone** | No layout LM dependency; no multi-page context |

```swift
enum StandaloneFieldLabelMapper {
    static func map(documentType: String, label: String, value: String) -> (profileKey: String, confidence: Double)?
}
```

---

## What stays non-ML (do not train)

| Signal | Why |
|--------|-----|
| PDF417 barcode (DL) | Already structured; build 56 gold standard |
| MRZ lines | ICAO standard; use when present |
| `TexasDriverLicenseParser` numbered rows | Deterministic, debuggable |
| `IndianPassportParser` / `PassportParser` after page select | Source of truth |

---

## Training → ship pipeline (per model)

```
manifest.json + local labels.jsonl (device OCR — gitignored)
        ↓
  scripts/export_training_rows.py → three Create ML CSVs
        ↓
  Create ML / coremltools (Mac)
        ↓
  trustnest.<name>.v1.mlpackage
        ↓
  apps/ios/DreamWorkApp/Resources/Models/<name>.mlpackage
        ↓
  Adapter: if bundled { run } else { skip }
```

### Export command (one step from test session → CSVs)

```bash
# Manifest-only (synthetic fixtures baked into the script)
python3 scripts/export_training_rows.py

# After appending local session labels (copy labels.jsonl.example first)
cp local-training/labels.jsonl.example local-training/labels.jsonl
python3 scripts/export_training_rows.py --labels local-training/labels.jsonl --output local-training/export
```

Writes `local-training/export/`:

| CSV | Create ML task | Columns |
|-----|----------------|---------|
| `doc-type-classifier.csv` | Text Classifier | `text`, `label` (= document type) |
| `passport-page-ranker.csv` | Tabular Classifier | page features → `is_biodata_page` (0/1) |
| `field-label-mapper.csv` | Text Classifier | `text` (= `doc_type\tlabel\tvalue`), `label` (= profile_key or `_none_`) |

Append to `local-training/labels.jsonl` after each device/simulator test (never commit — see `local-training/.gitignore`).

Each model directory is independent:

```
Resources/Models/
  DocumentTypeClassifier.mlpackage/   # trustnest.doc-type.v1
  PassportPageRanker.mlpackage/       # trustnest.passport-page.v1
  FieldLabelMapper.mlpackage/         # trustnest.field-label.v1
```

`ModelArtifactRegistry` already has slots; add three new slots with `standalone: true` and `loadState: .notInstalled` until artifacts exist.

---

## Phased rollout

| Phase | Ship | Models |
|-------|------|--------|
| **Now (build 57)** | Rules + MRZ + barcode + manifest | None required |
| **Phase A** | Doc-type classifier bundled | `trustnest.doc-type.v1` only |
| **Phase B** | Passport page ranker bundled | `trustnest.passport-page.v1` only |
| **Phase C** | Field-label hints | `trustnest.field-label.v1` only |

Each phase is a **separate TestFlight build**; omitting a model must not change behavior (DL unchanged).

---

## Success metrics (per model)

| Model | Pass when |
|-------|-----------|
| doc-type | SSN boilerplate fixture → `ssnCard` ≥ 0.9; DL fixture still → `driversLicense` |
| passport-page | Multi-page Indian fixtures → biodata page index correct; names/DOB improve |
| field-label | `rejectedFields` in manifest never emitted; clean fixtures unchanged |

---

## Related files

- Corpus: `apps/ios/DreamWorkAppTests/Fixtures/manifest.json`
- Parsers (unchanged truth path): `PassportParser.swift`, `IndianPassportParser.swift`, `DriverLicenseParser.swift`
- Merge pattern: `MachineReadableFieldExtractor.mergeTrusted`
- Lessons: `docs/fresh-start-lessons-and-principles.md` (photo E2E gate, T7)
