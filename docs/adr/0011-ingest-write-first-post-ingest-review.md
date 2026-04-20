# ADR 0011: Ingest pipeline writes first; review and correction after commit

## Status

Accepted

## Date

2026-04-19

## Context

Batch import and automated runs must not stall on a **per-document confirmation gate**; users still need confidence, edits, and sensitive-field safeguards. The product thesis (see `features-list.md` / `idea-brainstorming.md`) favors **persisting structured output first**, then surfacing quality issues in **import activity** and entity views.

## Decision

1. Successful structuring results **commit to SQLite** in the same transactional boundary as validated DDL and row writes (ADR 0005).
2. The UI exposes **post-ingest review**: confidence, source snippets, person assignment fixes, and merge/supersede flows.
3. **Sensitive-field policies** may still require **extra prompts** before first use or before copying to clipboard/extension fill, without blocking unrelated rows from landing in the DB.

## Consequences

**Positive**

- Large folder imports complete unattended; users correct outliers asynchronously.
- Aligns throughput expectations with local batch OCR.

**Negative**

- Risk of transient “bad data” in DB until corrected; mitigated by clear UI surfacing, provenance (ADR 0008), and optional quarantine flags for lowest-confidence rows if product requires it later.

**Follow-ups**

- If product adds **quarantine**, document it as a **Supersedes** extension to this ADR or a new ADR.
