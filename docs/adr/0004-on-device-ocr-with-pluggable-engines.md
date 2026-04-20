# ADR 0004: On-device OCR with a pluggable engine abstraction

## Status

Accepted

## Date

2026-04-19

## Context

OCR quality, latency, and packaging differ by OS (Apple Vision, Google ML Kit, Tesseract/Paddle/ONNX stacks). We need a consistent **internal artifact** (text + layout + confidence + geometry) for provenance UI and downstream structuring, independent of vendor.

## Decision

Define an internal **`OcrEngine` interface** and a normalized output model (`Document` → `Page` → `Block` with bounding boxes, script, confidence).

- Ship **platform-default engines** first (best battery and integration).
- Allow **alternate engines** behind the same interface for parity, table-heavy documents, or A/B evaluation.
- Store **immutable `extraction_run` records** keyed by engine id + model version + parameters so provenance stays interpretable when re-running OCR.

## Consequences

**Positive**

- Vendor swap without rewriting the structuring pipeline.
- Clear audit trail when OCR upgrades change extracted text.

**Negative**

- Multiple engines increase binary size and QA surface.
- Normalizing layout across engines requires careful testing on tables and multi-column forms.

**Follow-ups**

- Golden-file regression suite per engine for representative document types.
