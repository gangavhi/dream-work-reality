# Field mapping — git history analysis (ONNX vs what actually ran)

**Date:** 2026-05-30  
**Question:** Were we using an **ONNX field mapper ~40 MB INT8**? Why did first name, last name, DOB, driver license number mapping fail?  
**Related:** [trustnest-document-field-identification-investigation.md](./trustnest-document-field-identification-investigation.md) · [mobile-ml-model-strategy-brainstorm.md](./mobile-ml-model-strategy-brainstorm.md)

---

## Short answer

**No — an ONNX ~40 MB INT8 field mapper was never implemented or shipped in this repo.**

What existed instead:

| Layer | Status in git | What it actually is |
|-------|---------------|---------------------|
| **`ort.embed.v1` / `ort.field_type.v1`** | **Planned only** ([device-matrix.md](./device-matrix.md), ADR 0017) | Artifact IDs in docs; **no production `.onnx` field model** in app bundle |
| **`OrtIdentityOnnxSession`** | **Test fixture only** | Tiny `identity.onnx` in Rust tests — not field mapping |
| **`SemanticFieldLabelMapper`** | **Shipped** (build 30+) | **Hand-written synonym lists** + token overlap |
| **`LocalEmbeddingFieldMatcher`** | **Shipped** (commit `3cb1a58`) | **Bag-of-words cosine** — comments say *“MiniLM slot TBD”*; **not** MiniLM, **not** ONNX |
| **`local_document_mapper.rs`** | **Shipped** (build 28+) | **Regex + label\|value heuristics**; GGUF optional until ML-only |
| **Qwen GGUF + llama.cpp** | **Shipped** (`3cb1a58` onward) | **Only** extraction path after “strict ML-only” — when model present |

The **~40 MB ONNX** figure appears only in **architecture docs** and the **2026-05-30 brainstorm** as a **future recommendation**, not as something that ran in TestFlight.

---

## Git timeline (field extraction)

| Commit | Date / build | Extraction behavior |
|--------|--------------|---------------------|
| **`4da5cab`** | Build **28** — “on-device field extraction” | Rust **`heuristic.on_device.v1`**: `extract_fields` (regex SSN/email/phone/dates/DL#), `apply_label_value_pairs`, `apply_mrz_hints`. **No GGUF inference** even if file exists (header check only). |
| **`eb79fc0`** | Build **30** — multi-agent architecture | **Hybrid:** MRZ/PDF417 → layout pairs → `OnDeviceFieldMapper` (same Rust heuristics) → optional network LLM (disabled) → **`UniversalDocumentParser`** regex fallback → NER stub (empty). |
| **`8e02c53`** | Build **34** | Open-vocabulary / extension keys; richer template + semantic paths. |
| **`3cb1a58`** | May 25 — **“strict local ML-only pipeline”** | **Removed** template extraction, machine-readable boosters, `UniversalDocumentParser` fallback, learned corrections from scan path. **Only** `OnDeviceFieldMapper` → Rust **`generate_constrained_json`** (Qwen GGUF). Added `LocalEmbeddingFieldMatcher` but **not wired as primary extractor** in ML-only path. |
| **`0d846a1`** | Storage planner GGUF | SQL routing model (separate from field mapping). |
| **`bbabea1`–`90dfd9d`** | Crash fixes | 3B→0.5B Qwen, defer storage, manual extract on iPhone. |

---

## Evidence: ONNX was never the field mapper

### 1. Rust ONNX code is a stub

```1:25:core/dreamwork_core/src/inference/onnx_ort.rs
//! ONNX Runtime execution provider wiring (ADR 0017).
pub struct OrtIdentityOnnxSession { ... }
// include_bytes!("../../fixtures/identity.onnx") — identity passthrough test only
```

`project-requirements-and-implementation-gap.md` explicitly lists: **“ONNX on-device models | Missing (Rust stub)”**.

### 2. “MiniLM field embedder” is registry placeholder

`ModelArtifactRegistry.swift` defines slot `.fieldEmbedder` → *“MiniLM field embedder”* but **no `.onnx` or `.mlmodelc` is bundled** for it.

### 3. LocalEmbeddingFieldMatcher is not neural

```3:4:apps/ios/DreamWorkApp/Sources/Intelligence/Embeddings/LocalEmbeddingFieldMatcher.swift
/// Offline embedding-style label matcher. Today this is a deterministic token-vector cosine
/// matcher; the MiniLM/CoreML slot can replace `vector(for:)` without changing callers.
```

Added in **`3cb1a58`** as a **stand-in** until real embeddings ship.

### 4. Build 28 mapper was pure heuristics

At `4da5cab`, `map_document_fields` always ran:

```rust
let mut fields = extract_fields(&req.layout_text);
apply_label_value_pairs(&req.layout_text, &mut fields);
apply_mrz_hints(&req.layout_text, &mut fields);
// engine: heuristic.on_device.v1 — no llama call
```

---

## Why first name, last name, DOB, DL number mapping failed

Your understanding matches the **May 25 investigation** ([trustnest-document-field-identification-investigation.md](./trustnest-document-field-identification-investigation.md)). The failures were **not** because a bad ONNX model shipped — it’s because **non-neural heuristics + broken layout pairing** were doing the job, then **ML-only removed the fallbacks** that sometimes worked.

### Primary causes (confirmed in code + E2E notes)

| Cause | Effect on DL / identity fields |
|-------|--------------------------------|
| **Layout pairing treats single tokens as “labels”** (`OcrLayoutSerializer`) | Values like `SHARMA` mis-paired → wrong keys for **last name**, **first name** |
| **Open-vocabulary extension keys** when synonyms miss | Junk keys instead of `legal_first_name`, `legal_last_name`, `date_of_birth`, `drivers_license_number` |
| **Heuristic Rust regex** | Works sometimes for **DL#**, **DOB** when formatted clearly; fails on varied layouts |
| **`SemanticFieldLabelMapper` synonyms** | Can map *“First Name”* → `legal_first_name` **only if** label|value pairing is correct first |
| **ML-only (`3cb1a58`)** removed | MRZ path, templates (incl. DL regions), `UniversalDocumentParser` — fewer correct hits for structured IDs |
| **Qwen GGUF** | Intended fix but often **missing in IPA**, **crashes when loaded**, or **slow** — so fields still empty/wrong in TestFlight |

Example from investigation (passport E2E): simulated blocks produced  
`legal_last_name=Name`, `legal_middle_name=Date Of Birth Sharma Given` — classic **pairing + heuristic** failure, not ONNX.

---

## What *did* work better (historically)

Before **`3cb1a58`**, structured docs could get correct fields from:

- **MRZ / PDF417** (`MachineReadableFieldExtractor`) — strong for passport/DL barcodes  
- **`DocumentTemplateAgent`** — DL coordinate regions + regex (build 34–35)  
- **`UniversalDocumentParser`** — regex fallback when other paths empty  
- **Dedicated `DriverLicenseScanner`** flow (older forms path)

The **strict ML-only** change traded those deterministic paths for **one GGUF JSON parser**, which is heavier and was unreliable on device.

---

## Correcting the mental model

| You may have thought | Git / code reality |
|----------------------|-------------------|
| ONNX INT8 field mapper ~40 MB in production | **Never built** — only `ort.*` IDs in docs + identity ONNX test |
| MiniLM embedding mapper | **Placeholder**; actual code = synonym list + token cosine |
| On-device extraction = neural | **Build 28–35:** mostly **heuristics**; **post-3cb1a58:** **Qwen GGUF only** on scan path |
| Poor mapping = wrong ONNX model | Poor mapping = **layout pairing + heuristics**; worse after **removing fallbacks** |

---

## Recommended path forward (after this analysis)

Given you **do not need document type** and you need **stable, correct profile fields** on 4–6 GB phones:

### Tier 1 — Restore structured extraction (fast win, low RAM)

Re-enable for **`ProfileSchema` canonical keys only** (not open vocabulary):

1. **MRZ / PDF417** merge on scan (zero extra model RAM)  
2. **Template + regex** for driver license / passport layouts (build 34 code still in repo; disabled in orchestrator)  
3. **Fix layout pairing** (`isFieldLabel` single-token rule) before any ML  
4. Keep **`SemanticFieldLabelMapper`** synonyms on corrected pairs  

**No 380 MB GGUF required** for typical DL fields if layout + MRZ + template are back.

### Tier 2 — Ship real small ONNX mapper (new work)

Implement what docs always described but never built:

- **`ort.field_mapper.v1`**: e.g. `all-MiniLM-L6-v2` INT8 (~22–40 MB)  
- Input: OCR **label string** (+ optional doc hint) → **`profile_key`**  
- Run **after** label|value pairing; validate values with regex  

Same Rust core + ORT on iOS (Core ML EP) and Android (NNAPI).

### Tier 3 — Optional GGUF (flagship / user tap only)

Use **SmolLM2-360M** or **Qwen 0.5B** only for **ambiguous** documents after Tier 1+2, **manual or deferred** — not auto after OCR.

### Do not repeat

- Calling synonym/heuristic stacks “ONNX”  
- ML-only pipeline with **no fallback** until a bundled model is proven on **`ram_min` devices**  
- Separate classifier GGUF when doc type is out of scope  

---

## Commands to reproduce this analysis locally

```bash
# When LocalEmbeddingFieldMatcher was added (with ML-only commit)
git log --oneline -- apps/ios/DreamWorkApp/Sources/Intelligence/Embeddings/LocalEmbeddingFieldMatcher.swift

# Build 28 heuristic mapper (no llama)
git show 4da5cab:core/dreamwork_core/src/local_document_mapper.rs | head -80

# ML-only: heuristics removed from ExtractionAgent
git show 3cb1a58 -- apps/ios/DreamWorkApp/Sources/Intelligence/Agents/ExtractionAgent.swift

# Confirm no ort.field_mapper in manifest
cat apps/ios/DreamWorkApp/Resources/model-manifest.json
```

---

## Summary one-liner

**We never shipped an ONNX ~40 MB field mapper; we shipped synonym/heuristic mappers (and briefly a hybrid with templates/MRZ), then replaced them with Qwen GGUF-only extraction — which caused crashes and did not reliably fix first name, last name, DOB, or DL number. The best next step is restore structured non-LLM paths + fix layout pairing, then add a real small ONNX label→key model if needed.**
