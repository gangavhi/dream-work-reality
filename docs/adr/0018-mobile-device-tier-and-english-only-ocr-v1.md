# ADR 0018: Mobile device tier (latest flagship iPhone & Samsung) and English-only OCR for v1

## Status

Accepted

## Date

2026-04-25

## Context

We need an explicit **first-class hardware baseline** so inference (LLM tiers, ONNX EPs), OCR packaging, and QA matrices stay bounded. We also need a clear **language scope** for OCR v1 to avoid prematurely committing to multilingual engines, dictionaries, and regression assets.

Product intent remains **local-first** (ADR 0001); this ADR only narrows **which phones we optimize for first** and **which OCR languages we ship**.

## Decision

### 1) Primary mobile targets (v1 optimization)

Optimize performance, model sizes, and thermal behavior for **current-generation flagship devices** at ship time:

- **Apple:** latest **iPhone** flagship line (e.g. current **Pro / Pro Max** tier as the reference envelope for RAM, Neural Engine, and sustained performance).
- **Samsung:** latest **Galaxy S Ultra** (or equivalent **Samsung flagship** SKU sold in the same generation) as the Android reference envelope.

**Mid-tier and older devices** remain supported via **degraded tiers** (smaller quantized models, fewer concurrent jobs, optional CPU-only paths)—but **engineering acceptance tests and default bundles** target the two reference devices above.

Approximate expectation (not a hard minimum in code): **≥ 8 GB RAM** on reference SKUs, which informs default **LLM quantization** and whether a **“large” on-device model** ships in the default app bundle vs optional download.

### 2) OCR language scope (v1)

For v1 ingestion and document OCR:

- Support **English (`en`) only**.
- **Do not** commit product or engineering bandwidth to multilingual OCR accuracy, locale-specific segmentation, or multi-script layout tuning in v1.
- Architecture remains **pluggable** (ADR 0004); adding locales later is a **new ADR** when we expand language matrix and QA.

Implementation guidance:

- Prefer engine configs / models trained or tuned for **Latin script English** (including typical US-form alphanumeric mixes).
- Record `language_tag = "en"` on `extraction_run` metadata where applicable so provenance stays honest when multilingual OCR is added later.

## Consequences

**Positive**

- Faster iteration: one OCR QA corpus (English forms, IDs, letters).
- Clear messaging: “English documents first.”
- Reference devices simplify benchmarking LLM + ONNX stacks (ADR 0017).

**Negative**

- Users with non-English documents get **best-effort or unsupported** OCR until a follow-on ADR expands languages.
- Samsung SKU fragmentation still exists; “reference flagship” must be **named per release** in test matrices.

**Follow-ups**

- Maintain **[`docs/device-matrix.md`](../device-matrix.md)** each release train (exact QA SKUs + OS patch floors).
- When expanding OCR: ADR for **supported locales**, engine selection per locale, and golden-file sets per script.
