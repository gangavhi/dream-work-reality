# ADR 0008: Provenance and append-oriented field value history

## Status

Accepted

## Date

2026-04-19

## Context

Users need to trust **where a value came from**, correct mistakes, and see **what changed over time** (new passport, new address). Regulatory-adjacent UX and internal debugging both benefit from immutable lineage.

## Decision

- Maintain **`field_value_current`** (fast reads) and **`field_value_history`** (append-oriented versions with `effective_from` / `effective_until`).
- Each version links to **source** metadata: `document_id`, `extraction_run_id`, optional snippet coordinates, `model_id` + `prompt_hash` where LLM was used, and **manual edit** attribution.
- **Documents** have their own retention and deletion flows; deleting a document does not silently erase history without an explicit policy (product-defined); minimum technical behavior is **retain structured history with redacted pointer** if required.

Security-sensitive events (export, share, key rotation) go to an **append-only `audit_log`**.

## Consequences

**Positive**

- Review UI can show “why” with evidence.
- Corrections and supersession (e.g., new ID scan) are modeled consistently.

**Negative**

- Database growth; requires pruning/compaction policies and user controls.
- More complex queries; **views** and careful indexing are required.

**Follow-ups**

- Define **GDPR-style local erasure** semantics vs forensic retention for shared copies (ties to ADR 0009).
