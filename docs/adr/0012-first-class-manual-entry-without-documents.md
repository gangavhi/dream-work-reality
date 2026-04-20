# ADR 0012: First-class manual entry—users may populate local memory without scans or uploads

## Status

Accepted

## Date

2026-04-19

## Context

ADR 0001 commits to **no upload of document content to our backend by default**. Some users will extend that preference to **not** capturing or importing documents **on-device** at all: they still need **persistent structured memory** for **form filling** and household views.

Without an explicit decision, teams sometimes treat **OCR/import** as the “real” ingestion path and **manual forms** as a thin CRUD appendix—risking uneven features, weaker onboarding copy, and missed privacy-sensitive users.

## Decision

1. **Manual entry** (guided typing into person/household/field screens) is a **first-class** path: users may **populate and update** local relational memory **without** scan, photo, file, or folder import.
2. Data entered manually is stored in the **same** SQLite model and is available to the **browser extension**, **in-app form assist**, **gap prompts**, **history**, and **proximity sharing** (subject to scope), same as values produced by OCR or generative ingest—unless a feature **intrinsically** requires a document artifact (e.g. “attach this scan”), in which case the UI states that requirement clearly.
3. **Provenance** records source **`manual`** (and timestamps/edits as elsewhere). Manual rows **do not** imply a linked `document_id` until the user optionally adds one later.
4. **Product and UX** must present **“Enter manually”** (or equivalent) with **equal prominence** to capture/import where appropriate—not buried in advanced settings.

## Consequences

**Positive**

- Aligns with **privacy-minimal** users and **fast** onboarding when documents are not available.
- Avoids an **OCR-only** product posture; reduces pressure to process files the user never wanted on device.

**Negative**

- **No OCR snippet** for provenance on manual fields—trust and correction rely on **clear UI**, optional **effective dates**, and user edits.
- QA must cover **manual-only** journeys for every major flow that assumes “something was ingested.”

**Follow-ups**

- Telemetry (if any): distinguish **manual-only vaults** vs mixed sources for product health—**without** logging field values.
