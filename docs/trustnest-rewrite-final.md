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
| **Data model** | **Data-centric, not document-centric** — canonical fields are source of truth; documents are evidence only |
| **3 layers** | **A** classify → **C** document→field mapping (**MOST IMPORTANT**) → **B** canonical profile fields |
| **Storage** | **OCR raw data only** in `extraction_run`; **no** stored images/PDFs |
| **Accuracy first** | OCR is mostly fine; **field mapping** was the failure — fix mapping before more ML |
| **Pipeline** | CAPTURE (ephemeral) → OCR → EXTRACT → REVIEW → canonical SQLite fields |
| **Extraction order** | MRZ/barcode → type extractor → label-anchored → **stop** (empty beats wrong) |
| **Lineage** | Every canonical value traceable to `extraction_run_id`, manual edit, form write-back, or proximity share |
| **Share** | Proximity only — scoped **canonical field groups**, TTL, zero cloud egress |
| **Rollout** | **Single phase** — all layers and ship gates pass together before release |

---

## Three-layer model

```text
Layer B — Canonical schema (SOURCE OF TRUTH)
          first_name, ssn, driver_license_number, …
                              ▲
                              │ user-confirmed mapping
Layer C — Document → Field Mapping (MOST IMPORTANT)
          passport → passport_number, passport_expiry, …
          w2 → ssn, employer_name, income
          + extraction_run OCR JSON + lineage
                              ▲
                              │ classify + OCR
Layer A — Document types (CLASSIFICATION ONLY)
          passport, w2, utilityBill, …
```

**Fix:** Do not organize the vault as “Identity Documents → Passport, DL, SSN card.” Real systems store **universal fields**; documents only **update** them.

---

## Layer A — Document types (classification)

| Category | Types |
|----------|-------|
| Identity | Passport, driver’s license / state ID, birth certificate, SSN card |
| Financial / tax | W-2, 1099, tax returns, bank statements, pay stubs |
| Address proof | Utility bills, lease agreements, bank statements |
| Education | Transcripts, degree certificates, immunization records, student ID |
| Healthcare | Insurance card, vaccination records, medication list, medical records |
| Immigration / travel | Visa documents, work authorization (EAD), immigration forms (I-94) |
| Family / emergency | Marriage certificate, children’s birth certificates, emergency contacts |

**Note:** `ssn` is a **field** in Layer B, not a document. SSN card, W-2, and 1099 are evidence sources.

---

## Layer B — Canonical schema (core)

| Group | Key fields |
|-------|------------|
| **Personal identity** | `full_name`, `first_name`, `last_name`, `date_of_birth`, `gender`, `nationality` |
| **Government IDs** | `ssn`, `passport_number`, `driver_license_number`, `visa_number`, `work_authorization_number` + expiry keys |
| **Contact & address** | `current_address`, `mailing_address`, `phone_number`, `email` |
| **Financial** | `bank_account_number`, `routing_number`, `employer_name`, `income`, `pay_frequency` |
| **Education** | `highest_degree`, `institution_name`, `graduation_year`, `vaccination_status[]` |
| **Healthcare** | `insurance_provider`, `policy_number`, `blood_type` |
| **Family / emergency** | `emergency_contacts[]`, `dependents[]`, `marital_status` |

**Legacy rename:** `insurance_carrier` → `insurance_provider`, `insurance_member_id` → `policy_number`, `drivers_license_*` → `driver_license_*`.

### Layer C — Passport example (document → fields)

| Canonical field | OCR anchor |
|-----------------|------------|
| `first_name` | MRZ TD3 given names |
| `last_name` | MRZ TD3 surname |
| `date_of_birth` | MRZ TD3 DOB |
| `nationality` | MRZ country code |
| `passport_number` | MRZ document number |
| `passport_expiry` | MRZ expiry |

**Does not map:** `ssn`, `driver_license_number`, `insurance_provider`.

All document mapping tables: [Layer C § Document → Field Mapping](fresh-start-lessons-and-principles.md#layer-c--document--field-mapping-most-important).

---

## What we store

| Persisted | Not persisted |
|-----------|---------------|
| Layer B: `field_value_current` + `field_value_history` | Document images / PDFs |
| Layer C: `extraction_run` OCR JSON + lineage | Document library / thumbnails |

---

## Single-phase ship gates

### Extraction (photo E2E → canonical fields)

| Evidence document | Canonical fields must populate |
|-------------------|-------------------------------|
| Texas DL | `first_name`, `last_name`, `date_of_birth`, `driver_license_number`, `driver_license_expiry` |
| US Passport | name, DOB, `passport_number`, `passport_expiry` |
| SSN card | name, `ssn` |
| Insurance card | name, DOB, `insurance_provider`, `policy_number`, `insurance_group_id` |

### Product gates

- [ ] **Canonical schema** — profile, form fill, share use Layer B keys only  
- [ ] **Lineage** — every field shows evidence `document_type` + `extraction_run_id`  
- [ ] **Expiry** — government identifier groups guarded at form fill  
- [ ] **Proximity share** — canonical field groups, TTL, NFC+BLE, zero egress  
- [ ] **OCR-only** — no image bytes after `extraction_run` save  

---

## Architecture

```text
Scan → Vision OCR → Classify (Layer A) → Extract → Review → Save canonical fields (Layer B)
                                                                    ↓
                                              Form matcher reads Layer B + lineage (Layer C)
```

**Do not port:** document-centric vault UI, orchestrator agents, default LLM/ONNX paths, stored document files.

---

## Branches

| Branch | Owner |
|--------|-------|
| `TrustNest_Rewrite_Sreeni` | Sreeni |
| `TrustNest_Rewrite_Gnaga` | Ganga |
| `TrustNest_Rewrite_Srikanth` | Srikanth |

---

## Version history

| Version | Change |
|---------|--------|
| 2.0 FINAL | Initial blueprint + segregation taxonomy |
| **2.1** | Data-centric 3-layer model |
| **2.2** | **Layer C document → field mapping** (MOST IMPORTANT) — per-type tables |

---

*TrustNest Rewrite Final Blueprint v2.2 — June 2026.*
