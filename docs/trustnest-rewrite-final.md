# TrustNest Rewrite — Final Blueprint

**Status:** FINAL  
**Branch:** `docs/fresh-start-principles`  
**Date:** June 2026  
**Audience:** Sreeni, Ganga, Srikanth — anyone implementing the TrustNest / DreamWork rewrite  

**Companion docs (read in order):**

1. **This file** — executive blueprint and ship checklist  
2. [fresh-start-lessons-and-principles.md](fresh-start-lessons-and-principles.md) — full lessons, anti-patterns, gates, decision log  
3. [fresh-start-implementation-baseline.md](fresh-start-implementation-baseline.md) — what exists in the legacy codebase today  
4. [architecture.md](architecture.md) — system architecture (updated for rewrite direction)

---

## Executive summary

TrustNest helps households **fill forms** (school, medical, government, in-app) from a **trusted local vault** — not from retyping the same fields every year.

| Principle | Decision |
|-----------|----------|
| **North star** | Confirmed form automation from a household SQLite vault |
| **Storage** | **OCR raw data only** — normalized JSON in `extraction_run`; **no** stored images/PDFs |
| **Accuracy first** | OCR is mostly fine; **field mapping** was the failure — fix mapping before more ML |
| **Pipeline** | CAPTURE (ephemeral) → OCR → EXTRACT → REVIEW → SQLite |
| **Extraction order** | MRZ/barcode → type extractor → label-anchored → **stop** (empty beats wrong) |
| **Document model** | Seven [segregation tiers](#document-categories) — classify once, extract once |
| **Lineage** | Every profile value traceable to `extraction_run_id`, manual edit, form write-back, or proximity share |
| **Expiry** | Local reminders + form-fill guardrails when DL/passport/state ID datasets are stale |
| **Share** | Proximity only (NFC + BLE) — scoped presets, TTL, zero cloud egress |
| **Rollout** | **Single phase** — all categories and all ship gates pass together before release |
| **Tests** | Photo fixture E2E (Vision OCR → extract) is the gate; synthetic OCR lines are not enough |

---

## What we are building

```text
Scan (ephemeral image) → OCR JSON → Extract → User review → SQLite profiles
                                                              ↓
                                    Form fill (confirmed) ← lineage + expiry checks
                                                              ↓
                                    Proximity share (scoped, TTL, no internet)
```

**We are not building:** a document archive, a 15-agent orchestrator, default ONNX/GGUF/LLM paths, or cloud-synced PII.

---

## What we store

| Persisted in SQLite | Never persisted |
|---------------------|-----------------|
| `extraction_run` — blocks, bounds, `fullText` | JPEG / PNG / PDF / HEIC bytes |
| `field_value_current` + `field_value_history` | Thumbnails, document library folders |
| Lineage: `extraction_run_id`, `document_type`, `scanned_at` | `document_id` / file paths to scans |

Users can audit **what OCR captured** on a past run. They cannot reopen the original photo unless they **scan again**.

---

## Document categories

All seven tiers ship in **one rollout**. Build extractors in priority order; release when every gate is green.

| # | Category | Examples | Priority extractors |
|---|----------|----------|---------------------|
| 1 | **Identity** (critical) | Passport, DL/state ID, birth certificate, SSN card | Texas DL, passport, SSN, state ID |
| 2 | **Tax & financial** | W-2, 1099, tax returns, bank details, pay stubs | `TaxFormExtractor`, `bankStatement` |
| 3 | **Address proof** | Utility bills, lease, bank statements | `AddressProofExtractor` |
| 4 | **Education** | Transcripts, degrees, immunization records, student ID | `EducationDocumentExtractor` |
| 5 | **Healthcare** | Insurance card, vaccination, medications, medical records | `InsuranceCardExtractor` |
| 6 | **Immigration / travel** | Visa, work authorization, immigration forms | `ImmigrationDocumentExtractor` |
| 7 | **Family / emergency** | Marriage cert, children's birth certs, emergency contacts | `FamilyDocumentExtractor` |

**Classifier rule:** utility bills must **not** trigger DL/passport parsers.

Full field keys and anchors: [fresh-start-lessons-and-principles.md § Household document segregation](fresh-start-lessons-and-principles.md#household-document-segregation-vault-taxonomy).

---

## Core profile keys (v1 schema)

```text
legal_first_name, legal_last_name, display_name, date_of_birth,
ssn, drivers_license_number, drivers_license_state, drivers_license_expiry,
passport_number, passport_expiry,
state_id_number, state_id_expiry,
insurance_carrier, insurance_member_id, insurance_group_id
```

Expand schema per category as extractors land. **Expiry keys are required** for reminders and form guardrails.

---

## Single-phase ship gates

All must pass before TestFlight / release:

### Extraction (photo E2E)

| Document | Must extract correctly |
|----------|------------------------|
| Texas DL | name, DOB, DL#, expiry |
| US Passport | name, DOB, passport #, expiry |
| SSN card | name, SSN |
| Insurance card | name, DOB, carrier, member ID, group ID |
| State ID (child) | name, DOB |

### Product gates

- [ ] **Lineage** — profile + form fill show source per field (`extraction_run_id` or manual)
- [ ] **Expiry** — local notifications; form fill blocks stale DL/passport without user ack
- [ ] **Form fill** — confirmed automation only; child vs parent subject explicit
- [ ] **Proximity share** — scoped presets, TTL, NFC+BLE, zero egress, revoke
- [ ] **OCR-only storage** — no image bytes on disk after `extraction_run` save

Detail scenarios: [acceptance matrix and gates](fresh-start-lessons-and-principles.md#acceptance-matrix-definition-of-basic-things-right).

---

## Architecture (rewrite)

```text
iOS:  Camera → VisionOcrAdapter → DocumentClassifier → ExtractorRegistry → GroundingValidator → ScanReviewView
                                                                                      ↓
Rust: dreamwork_ocr_apply_normalized_json → resolvePerson → save_manual_entry_json → field_value_history
                                                                                      ↓
      form matcher + dataset_health + proximity grants → SQLite
```

**Do not port to rewrite:** `DocumentIntelligenceOrchestrator`, `ExtractionAgent` multi-router, `PersonNameResolver` global post-processor, `UniversalDocumentParser` as default, knowledge graph / vector memory, GenAI/Ollama default path, ONNX/GGUF slots.

---

## Implementation checklist (condensed)

| Workstream | Key deliverables |
|------------|------------------|
| **Foundation** | Photo corpus per tier; `FieldAccuracyScorecard` |
| **Pipeline** | Vision OCR → classifier ≥95% → extractors per registry → grounding validator |
| **Vault** | `extraction_run` OCR JSON; profile save; lineage in SQLite ([ADR 0008](adr/0008-provenance-and-field-value-history.md)) |
| **Freshness** | `dataset_health`; local expiry notifications |
| **Form fill** | Rules-first matcher; preview with lineage; expiry intercept |
| **Share** | Scoped grants; NFC+BLE; `foreign_provenance` ([ADR 0009](adr/0009-proximity-sharing-ble-secure-channel-time-bound-grants.md)) |
| **Release** | All ship gates green; TestFlight on physical cards (sanitized) |

Full checklist: [Implementation rollout](fresh-start-lessons-and-principles.md#implementation-rollout-single-phase).

---

## Non-negotiables (decision log)

| Never | Always |
|-------|--------|
| Store document images/PDFs | Persist OCR JSON + confirmed fields |
| Guess name/DOB/SSN from flat text | Anchor-based or MRZ/barcode extraction |
| Silent form autofill | User confirms every fill batch |
| Share via cloud/upload fallback | Proximity transfer only |
| Fill expired ID silently | Prompt rescan or explicit override |
| Ship parser without photo E2E test | Vision OCR → extract → assert on PNG fixtures |
| Empty field vs wrong guess | **Empty wins** |

Full log: [Decision log](fresh-start-lessons-and-principles.md#decision-log-pre-decided--do-not-re-litigate).

---

## Branches for parallel rewrite work

| Branch | Owner |
|--------|-------|
| `TrustNest_Rewrite_Sreeni` | Sreeni |
| `TrustNest_Rewrite_Gnaga` | Ganga |
| `TrustNest_Rewrite_Srikanth` | Srikanth |

All branches fork from `ganga-2026-05-16-2`. Read this blueprint and the lessons doc **before** writing extraction code.

---

## Version history

| Version | Date | Change |
|---------|------|--------|
| 1.0 | May 2026 | Initial lessons document |
| 1.4 | Jun 2026 | Document segregation taxonomy |
| 1.5 | Jun 2026 | Single-phase rollout |
| 1.6 | Jun 2026 | OCR raw data only — no document files |
| **2.0 FINAL** | Jun 2026 | This blueprint; principles doc marked final |

---

*TrustNest Rewrite Final Blueprint — `docs/fresh-start-principles`, June 2026.*
