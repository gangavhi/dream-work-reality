# TrustNest Rewrite — Final Blueprint

**Status:** FINAL  
**Repository:** [gangavhi/dream-work-reality](https://github.com/gangavhi/dream-work-reality)  
**Branch:** `docs/fresh-start-principles` (also synced to `ganga-2026-05-16-2`)  
**Date:** June 2026  
**Audience:** Sreeni, Ganga, Srikanth — anyone implementing the TrustNest / DreamWork rewrite  

**Companion docs (read in order):**

1. **This file** — executive blueprint (stakeholders)  
2. **[trustnest-rewrite-implementation.md](trustnest-rewrite-implementation.md)** — **IMPLEMENTATION DOCUMENT** (engineering — build from this)  
3. [fresh-start-lessons-and-principles.md](fresh-start-lessons-and-principles.md) — lessons, anti-patterns, full Layer C detail  
4. [fresh-start-implementation-baseline.md](fresh-start-implementation-baseline.md) — legacy codebase inventory  
5. [architecture.md](architecture.md) — system architecture

---

## Executive summary

TrustNest helps households **submit forms** (school, medical, government, in-app) — **auto-fill typed fields** and **attach proof documents** — without retyping or re-scanning every year.

| Principle | Decision |
|-----------|----------|
| **North star** | Confirmed form submission: field auto-fill + document attach from local vault |
| **Dual path** | **Fields** → Layer C extract → Layer B vault · **Uploads** → submission stash auto-save on scan |
| **Data model** | **Data-centric** for typed fields; **scoped file stash** for vendor uploads — not a general document library |
| **3 layers** | **A** classify → stash? + form-relevant? → **C** mapping (**MOST IMPORTANT**) → **B** canonical fields |
| **Form-relevance** | Extract only unique form-fill fields; W-2/1099/pay stub → **no extract**; birth cert → **stash only** |
| **Auto-save** | Stash-listed types save on scan: `{Type} — {Person} — {date}` |
| **Storage** | SQLite: metadata + fields + OCR JSON · **Filesystem:** encrypted files for stash types (never BLOBs in DB) |
| **Pipeline** | CAPTURE → OCR → CLASSIFY → **STASH?** → **EXTRACT?** → REVIEW → submit (fill + attach) |
| **Extraction order** | MRZ/barcode → type extractor → label-anchored → **stop** (empty beats wrong) |
| **Lineage** | Every field traceable to `extraction_run_id`, manual edit, form write-back, or proximity share |
| **Share** | Proximity only — canonical field groups, TTL, zero cloud egress |
| **Rollout** | **Single phase** — fields, stash, attach, lineage, expiry, share together |

---

## Two jobs on vendor forms

| Job | School / doctor / DMV example | TrustNest |
|-----|------------------------------|-----------|
| **Fill fields** | Name, DOB, insurance member ID, address | Scan → extract → auto-fill |
| **Upload proof** | Immunization PDF, birth certificate, utility bill, insurance card photo | Scan → **auto-save** → attach at submit |

Vendors often require **both** on one submission. TrustNest covers each with a separate path.

---

## Three-layer model

```text
Layer B — Canonical schema (SOURCE OF TRUTH for typed fields)
          first_name, ssn, driver_license_number, current_address, …
                              ▲
                              │ user-confirmed mapping
Layer C — Document → Field Mapping (MOST IMPORTANT)
          passport → passport_number, passport_expiry, …
          insuranceCard → insurance_provider, policy_number, …
          + extraction_run OCR JSON + lineage
                              ▲
                              │ form_relevant gate + OCR
Layer A — Document types (CLASSIFICATION ONLY)
          passport, utility_bill, birthCertificate, …
```

**Rule:** Profile navigation uses **canonical fields** (Layer B), not document-type folders.

---

## Form-relevant extract allowlist (Layer C)

Extract **only** when a document supplies canonical fields that form matchers use and that are not already covered by passport/DL/state ID.

| `document_type` | Key fields extracted |
|-----------------|---------------------|
| `passport` | name, DOB, `passport_number`, `passport_expiry`, nationality |
| `driversLicense` | name, DOB, DL#, state, expiry, `current_address` |
| `stateId` | name, DOB, state ID#, expiry |
| `ssnCard` | name, `ssn` |
| `insuranceCard` | name, DOB, provider, policy#, group ID |
| `utility_bill`, `lease` | `current_address` |
| `bankStatement` | address, routing/account (direct deposit) |
| `immunizationRecord` | `vaccination_status[]` |

**Classify-only (no field extract):** `birthCertificate`, `marriageCertificate`, `taxReturn`, `w2`, `form1099`, `payStub`, `transcript`, `degree`, `studentId`, medical records, `unknown`, receipts.

**Birth certificate:** stash file for school upload; identity fields come from passport/state ID/DL.

Full mapping tables: [Layer C § Document → Field Mapping](fresh-start-lessons-and-principles.md#layer-c--document--field-mapping-most-important).

---

## Submission document stash (auto-save on scan)

When user scans a **stash-listed** type, the app **automatically** saves the encrypted file locally for form upload.

| `document_type` | Auto-stash | Field extract | Typical vendor use |
|-----------------|:----------:|:-------------:|-------------------|
| `immunizationRecord` | ✅ | ✅ | School health form upload |
| `birthCertificate` | ✅ | ❌ | School age verification |
| `utility_bill`, `lease` | ✅ | ✅ | Proof of residence |
| `insuranceCard` | ✅ | ✅ | Medical/school card photo |
| `driversLicense`, `stateId`, `passport` | ✅ | ✅ | ID verification upload |
| `bankStatement` | ✅ | partial | Benefits / loan proof |
| W-2, 1099, pay stub, receipts, unknown | ❌ | ❌ | — |

**Display name:** `Immunization Record — Emma Chen — 2026-06-01`  
**Rescan:** new file supersedes current for same person + type; history retained.  
**Setting:** “Automatically save documents for form upload” — on by default.

**Form attach:** Matcher detects file upload slot → proposes stored doc for person + type → user confirms.

Full spec: [Submission document stash](fresh-start-lessons-and-principles.md#submission-document-stash-upload-at-form-submit).

---

## Auto form fill extraction matrix (mandated documents)

| Document | Extract fields | Stash file | Key Layer B fields |
|----------|:--------------:|:----------:|-------------------|
| Passport | ✅ | ✅ | name, DOB, `passport_number`, `passport_expiry`, nationality |
| Driver’s license | ✅ | ✅ | name, DOB, DL#, state, expiry, `current_address` |
| State ID | ✅ | ✅ | name, DOB, state ID#, expiry |
| SSN card | ✅ | ❌ | name, `ssn` |
| Insurance card | ✅ | ✅ | name, DOB, provider, policy#, group ID |
| Utility bill / lease | ✅ | ✅ | `current_address`, name (optional) |
| Bank statement | ✅ | ✅ | address, `routing_number`, `bank_account_number` |
| Immunization record | ✅ | ✅ | `vaccination_status[]`, patient name |
| Visa / EAD / I-94 | ✅ | ❌ | auth/visa #, expiry, name |
| Birth certificate | ❌ | ✅ | — (upload only) |

Full table: [Auto form fill extraction matrix](fresh-start-lessons-and-principles.md#auto-form-fill-extraction-matrix-mandated-documents).

---

## Document file storage (SQLite metadata + encrypted files)

Submission documents use a **split store** — SQLite is **not** used for image/PDF bytes.

```text
SQLite (SQLCipher)                    Encrypted filesystem
─────────────────────                 ─────────────────────────────
stored_submission_document  ────────► submission_docs/{person}/{type}/current.enc
  • display_name, mime_type, sha256     • AES-GCM encrypted bytes
  • file_path (pointer only)          • NSFileProtectionComplete
  • is_current, superseded_at           • excluded from iCloud backup
```

| In SQLite | On disk |
|-----------|---------|
| `id`, `person_id`, `document_type`, `display_name` | JPEG / PNG / HEIC / PDF bytes |
| `file_path`, `mime_type`, `file_size_bytes`, `sha256` | |
| `scanned_at`, `extraction_run_id`, `is_current` | |

**Owners:** Rust = metadata CRUD + lookup · Swift = encrypt/write/read files · Extension = decrypt stream into form upload.

**Never:** SQLite BLOBs for scans · Photo Library · cloud sync.

Full spec: [Document file storage](fresh-start-lessons-and-principles.md#document-file-storage-sqlite-metadata--encrypted-files).

---

## Layer C JSON contracts

**Classification (Layer A):**

```json
{
  "document_type": "immunizationRecord",
  "confidence": 0.94,
  "form_relevant": true
}
```

**Extraction (Layer C):**

```json
{
  "document_type": "passport",
  "form_relevant": true,
  "extracted_fields": {
    "full_name": "John Doe",
    "date_of_birth": "1990-01-01",
    "passport_number": "X1234567",
    "nationality": "USA",
    "expiry_date": "2032-05-01"
  }
}
```

**Stash-only (birth certificate):**

```json
{
  "document_type": "birthCertificate",
  "confidence": 0.91,
  "form_relevant": false,
  "extracted_fields": null,
  "submission_doc_id": "uuid-of-saved-file"
}
```

---

## What we store

| Persisted | Not persisted |
|-----------|---------------|
| Layer B: canonical fields + history (SQLite) | Random scan archive |
| Layer C: `extraction_run` OCR JSON + lineage (SQLite) | SQLite BLOBs for document images |
| `stored_submission_document` metadata only (SQLite) | Cloud document sync |
| Encrypted `.enc` files under `submission_docs/` (filesystem) | Receipts, unknown uploads |

---

## Pipeline

```text
1. CAPTURE        → image/PDF in memory
2. OCR            → Vision → extraction_run JSON
3. CLASSIFY       → Layer A document_type
4. SUBMISSION STASH? → whitelist → auto-save file + display name
5. FORM-RELEVANT? → extract allowlist → Layer C mapping
6. REVIEW+SAVE    → user confirms fields → Layer B + lineage

Form submit → auto-fill fields + propose stash attachments → user confirms
```

---

## Single-phase ship gates

### Extraction (photo E2E → canonical fields)

| Evidence document | Canonical fields must populate |
|-------------------|-------------------------------|
| Texas DL | `first_name`, `last_name`, `date_of_birth`, `driver_license_number`, `driver_license_expiry` |
| US Passport | name, DOB, `passport_number`, `passport_expiry` |
| SSN card | name, `ssn` |
| Insurance card | name, DOB, `insurance_provider`, `policy_number`, `insurance_group_id` |

### Submission stash + attach

- [ ] Immunization scan auto-saves with display name  
- [ ] Birth certificate scan auto-saves; no field extract  
- [ ] School form upload slot proposes matching stash file  
- [ ] Rescan supersedes prior file for same person + type  
- [ ] Document bytes on encrypted filesystem only — **no** SQLite BLOBs  

### Product gates

- [ ] **Canonical schema** — profile, form fill, share use Layer B keys only  
- [ ] **Form-relevance gate** — no field extract off allowlist  
- [ ] **Submission stash** — whitelist only; encrypted at rest; zero egress  
- [ ] **Lineage** — every field shows `extraction_run_id`  
- [ ] **Expiry** — government ID groups guarded at form fill  
- [ ] **Proximity share** — field groups only; TTL; NFC+BLE  

**Do not port:** document-centric vault UI, orchestrator agents, default LLM/ONNX paths, `UniversalDocumentParser` on general scan.

---

## Implementation branches

| Branch | Owner |
|--------|-------|
| `TrustNest_Rewrite_Sreeni` | Sreeni |
| `TrustNest_Rewrite_Gnaga` | Ganga |
| `TrustNest_Rewrite_Srikanth` | Srikanth |

Doc branches: `docs/fresh-start-principles`, `ganga-2026-05-16-2`.

---

## Version history

| Version | Change |
|---------|--------|
| 2.0 FINAL | Initial blueprint + household document taxonomy |
| 2.1 | Data-centric 3-layer model |
| 2.2 | Layer C document → field mapping (MOST IMPORTANT) |
| 2.3 | Layer C JSON output contracts |
| 2.4 | Form-relevant allowlist — no extract on irrelevant scans |
| 2.5 | Tightened extract list (birth cert classify-only; W-2/1099 deferred) |
| 2.6 FINAL | Dual path: field auto-fill + submission document stash |
| 2.7 | Document file storage: SQLite metadata + encrypted filesystem |
| 2.8 | Auto form fill extraction matrix by mandated document |
| **2.8 IMPL** | **[trustnest-rewrite-implementation.md](trustnest-rewrite-implementation.md)** — implementation document for engineering |

---

*TrustNest Rewrite Final Blueprint v2.8 — June 2026. Engineers: use [trustnest-rewrite-implementation.md](trustnest-rewrite-implementation.md).*
