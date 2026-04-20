# ADR 0001: Local-first storage; no document upload by default

## Status

Accepted

## Date

2026-04-19

## Context

The product handles highly sensitive documents and household data (identity, benefits, education, medical-adjacent). Users are sensitive to cloud aggregators and hard-to-revoke copies. Competitive positioning and trust require a clear default boundary: **what leaves the device**.

## Decision

1. **Canonical structured data** and **default document processing** (OCR, parsing, structuring) run **on the user’s device**.
2. **No upload of document content or extracted payloads** to our backend **unless** the user explicitly opts into a clearly labeled mode (if such a mode is ever offered).
3. Optional network services, when present, are limited to **non-content** concerns (see ADR 0010).

## Consequences

**Positive**

- Strong privacy story and simpler regulatory posture for the default path.
- Offline-capable ingestion and form assist remain credible.
- Users who **decline document capture entirely** can still use **manual entry** into local memory for form filling (see ADR 0012); the “no cloud document upload” rule does **not** force users through OCR.

**Negative**

- Model quality and latency are bound by **device capabilities**; older hardware needs tiered models and graceful degradation.
- Support and debugging are harder without server-side document logs; we rely on **opt-in diagnostics** and local tooling.

**Follow-ups**

- Product copy and consent flows must stay aligned with this ADR if cloud-assisted features are added later.
