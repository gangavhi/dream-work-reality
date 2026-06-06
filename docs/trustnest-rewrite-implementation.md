# TrustNest Rewrite — Implementation Document

**Status:** IMPLEMENTATION FINAL  
**Version:** 2.8  
**Repository:** [gangavhi/dream-work-reality](https://github.com/gangavhi/dream-work-reality)  
**Branches:** `ganga-2026-05-16-2` · `docs/fresh-start-principles`  
**Date:** June 2026  
**Audience:** Sreeni, Ganga, Srikanth — engineering implementation  

---

## How to use this document

| Read this | When |
|-----------|------|
| **This file** | Building the rewrite — schema, pipeline, extractors, gates, workstreams |
| [trustnest-rewrite-final.md](trustnest-rewrite-final.md) | Executive summary for stakeholders (1-page) |
| [fresh-start-lessons-and-principles.md](fresh-start-lessons-and-principles.md) | Why we rewrite, anti-patterns, full Layer C mapping detail |
| [fresh-start-implementation-baseline.md](fresh-start-implementation-baseline.md) | What exists in legacy codebase today |

---

## 1. Product goal

Help households **submit forms** (school, medical, government, in-app) by:

1. **Auto-filling typed fields** from a local canonical vault (Layer B)  
2. **Attaching proof documents** from a submission stash (encrypted files on disk)

**Constraints:** Zero cloud egress · confirmed automation only · empty beats wrong · single-phase rollout.

---

## 2. Architecture overview

```text
┌──────────── iOS ────────────┐     ┌──────────── Rust core ────────────┐
│ Camera / import             │     │ SQLite (SQLCipher)                │
│ Vision OCR                  │────►│  • field_value_current/history    │
│ Classifier                  │     │  • extraction_run (OCR JSON)      │
│ Extractor registry (Layer C)│     │  • stored_submission_document     │
│ Scan review UI              │     │  • form matcher + lineage         │
│ Submission file I/O (.enc)  │     │  • dataset health + proximity     │
│ Form fill + attach UI       │     └───────────────────────────────────┘
│ Extension (browser)         │
└─────────────────────────────┘
```

**Module ownership**

| Concern | Owner |
|---------|-------|
| OCR, classify, extract (layout) | Swift |
| Profile CRUD, lineage, matcher | Rust FFI |
| `extraction_run`, field history | Rust SQLite |
| `stored_submission_document` metadata | Rust SQLite |
| Encrypt/write/read submission files | Swift (Application Support) |
| Form file attach (decrypt stream) | Extension + Swift bridge |
| Expiry notifications | iOS `UNUserNotificationCenter` |
| Proximity share crypto | Rust `proximity/`; NFC/BLE in Swift |

---

## 3. Pipeline (implement exactly this)

```text
1. CAPTURE           → image/PDF bytes in memory
2. OCR               → Vision → NormalizedDocument → persist extraction_run JSON
3. CLASSIFY          → Layer A: document_type + confidence
4. SUBMISSION STASH? → if whitelist → encrypt file + insert stored_submission_document
5. FORM-RELEVANT?    → if extract allowlist → Layer C mapping → FieldSuggestion[]
6. REVIEW + SAVE     → user confirms → Layer B canonical fields + lineage

Form submit:
  • Matcher proposes field values from Layer B
  • Matcher proposes stash file for upload slots
  • User confirms → apply fields + attach files
```

**Extraction priority inside Layer C:** MRZ/barcode → type-specific extractor → label-anchored layout → **STOP** (no universal regex parser).

---

## 4. Three-layer data model

| Layer | Role | Persisted as |
|-------|------|--------------|
| **A — Classify** | `document_type` only | `extraction_run.document_type` |
| **C — Map** | Document → canonical fields (**MOST IMPORTANT**) | Extractor output + OCR JSON |
| **B — Vault** | Source of truth for form fill | `field_value_current` + history |

Profile UI and form matcher read **Layer B keys only** — never document-type folders.

---

## 5. Storage (split store)

### 5.1 SQLite tables (metadata + structured data)

**Never store image/PDF bytes in SQLite.**

| Table | Purpose |
|-------|---------|
| `person` | Household members |
| `field_value_current` | Latest canonical value per person + key |
| `field_value_history` | Superseded values + lineage ([ADR 0008](adr/0008-provenance-and-field-value-history.md)) |
| `extraction_run` | Normalized OCR JSON per scan |
| `stored_submission_document` | File metadata for form upload |

**`stored_submission_document` columns:**

```sql
CREATE TABLE stored_submission_document (
  id                TEXT PRIMARY KEY,
  person_id         TEXT NOT NULL,
  document_type     TEXT NOT NULL,
  display_name      TEXT NOT NULL,
  file_path         TEXT NOT NULL,   -- relative path; NOT blob
  mime_type         TEXT NOT NULL,
  file_size_bytes   INTEGER NOT NULL,
  sha256            TEXT NOT NULL,
  scanned_at        TEXT NOT NULL,
  extraction_run_id TEXT,
  is_current        INTEGER NOT NULL DEFAULT 1,
  superseded_at     TEXT,
  created_at        TEXT NOT NULL
);
```

**Display name (auto):** `{DocumentTypeLabel} — {PersonName} — {YYYY-MM-DD}`

### 5.2 Encrypted file vault (document bytes)

```text
Application Support/DreamWork/
├── vault.db
├── submission_docs/          # NSFileProtectionComplete; no iCloud backup
│   └── {person_id}/
│       └── {document_type}/
│           ├── current.enc
│           └── history/{uuid}.enc
└── thumbs/{submission_doc_id}.enc   # optional UI previews
```

- **Encryption:** AES-GCM per file; Keychain-backed key  
- **Max size:** 25 MB · **Formats:** JPEG, PNG, HEIC, PDF  
- **Atomic save:** write temp → fsync → SQLite row → rename → supersede prior  

---

## 6. Auto form fill extraction matrix (mandated documents)

What each document contributes to **typed field auto-fill** vs **file stash**.

| Document | Extract | Stash | Layer B fields | Typical USA forms |
|----------|:-------:|:-----:|----------------|-------------------|
| **Passport** | ✅ | ✅ | `first_name`, `last_name`, `full_name`, `date_of_birth`, `gender`, `nationality`, `passport_number`, `passport_expiry` | Travel, I-9, school ID |
| **Driver’s license** | ✅ | ✅ | `first_name`, `last_name`, `date_of_birth`, `driver_license_number`, `driver_license_state`, `driver_license_expiry`, `current_address` | School, medical, rental |
| **State ID** | ✅ | ✅ | `first_name`, `last_name`, `date_of_birth`, `state_id_number`, `state_id_expiry` | Child school forms |
| **SSN card** | ✅ | ❌ | `first_name`, `last_name`, `ssn` | Benefits, I-9 |
| **Insurance card** | ✅ | ✅ | `first_name`, `last_name`, `date_of_birth`, `insurance_provider`, `policy_number`, `insurance_group_id` | Medical, school nurse |
| **Utility bill** | ✅ | ✅ | `full_name` (opt), `current_address` | School proof of residence |
| **Lease** | ✅ | ✅ | `first_name`, `last_name`, `current_address` | School district, rental |
| **Bank statement** | ✅ | ✅ | `current_address`, `mailing_address`, `bank_account_number`, `routing_number` | Direct deposit, address proof |
| **Immunization record** | ✅ | ✅ | `first_name`, `vaccination_status[]` | School health vaccine table |
| **Visa / EAD / I-94** | ✅ | ❌ | name, `visa_number` or `work_authorization_number`, expiry | Immigration, I-9 |
| **Birth certificate** | ❌ | ✅ | — | School **upload only** |
| **W-2 / 1099 / pay stub** | ❌ | ❌ | — | Deferred (tax/loan niche) |

**Ship priority (photo E2E):** Texas DL → SSN card → insurance card → passport → child state ID.

---

## 7. Extractor registry

| `document_type` | Extractor | Primary OCR anchors |
|-----------------|-----------|---------------------|
| `driversLicense` | `TexasDriverLicenseExtractor` | AAMVA barcode; `4d. DL`; `3. DOB`; `8.` address |
| `passport` | `PassportExtractor` | MRZ TD3 |
| `ssnCard` | `SSNCardExtractor` | `###-##-####`; name above address |
| `insuranceCard` | `InsuranceCardExtractor` | `MEMBER ID`, `GROUP`, `SUBSCRIBER` |
| `stateId` | `StateIdExtractor` | `STATE ID`, `DOB:`, `ID:` |
| `utilityBill`, `lease` | `AddressProofExtractor` | service address block |
| `bankStatement` | `BankStatementExtractor` | mailing block, routing, account |
| `immunizationRecord` | `ImmunizationRecordExtractor` | vaccine row table |
| `visa`, `workAuthorization`, `immigrationForm` | `ImmigrationDocumentExtractor` | auth #, expiry |
| `birthCertificate`, `unknown`, receipts, … | **none** | classify-only; birth cert **stash only** |

**Do not port:** `UniversalDocumentParser`, `DocumentIntelligenceOrchestrator`, `ExtractionAgent`, `GenAIFieldMapper`, ONNX/GGUF default paths.

---

## 8. JSON contracts

### Layer A — classification

```json
{
  "document_type": "driversLicense",
  "confidence": 0.96,
  "form_relevant": true
}
```

### Layer C — extraction

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

Map `expiry_date` → `passport_expiry`, `service_address` → `current_address` on save.

### Stash-only — birth certificate

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

## 9. Layer B canonical keys (minimum v1)

```text
# Identity
first_name, last_name, full_name, date_of_birth, gender, nationality

# Government IDs
ssn, passport_number, passport_expiry,
driver_license_number, driver_license_state, driver_license_expiry,
state_id_number, state_id_expiry,
visa_number, visa_expiry, work_authorization_number, work_authorization_expiry

# Contact & address
current_address, mailing_address, phone_number, email

# Healthcare
insurance_provider, policy_number, insurance_group_id

# Financial (partial)
bank_account_number, routing_number

# Education / health
vaccination_status[]   # { vaccine, dose_date, site }
```

**Legacy renames:** `insurance_carrier` → `insurance_provider` · `insurance_member_id` → `policy_number` · `drivers_license_*` → `driver_license_*`

---

## 10. Implementation workstreams (single phase)

Build in this order. **Do not ship** until all gates in §11 pass.

### WS-1 — Pipeline foundation

- [ ] Camera + PNG import shell
- [ ] Vision OCR → `extraction_run` persist
- [ ] `DocumentClassifier` → type + confidence
- [ ] Form-relevance gate + stash gate (branch pipeline)
- [ ] `ScanReviewView` with source badges (`MRZ`, `Layout`, `Empty`)

### WS-2 — Extractors (photo E2E first)

- [ ] `TexasDriverLicenseExtractor`
- [ ] `SSNCardExtractor`
- [ ] `InsuranceCardExtractor`
- [ ] `PassportExtractor`
- [ ] `StateIdExtractor`
- [ ] `AddressProofExtractor`, `BankStatementExtractor`, `ImmunizationRecordExtractor`
- [ ] Grounding validator: value must appear in OCR span

### WS-3 — Submission stash

- [ ] Swift `SubmissionDocumentStore` — encrypt/write/read `.enc`
- [ ] Rust `stored_submission_document` CRUD + supersede
- [ ] Auto-save on stash-listed scan; settings toggle
- [ ] People → Documents list UI

### WS-4 — Vault + lineage (Rust)

- [ ] `field_value_current` + `field_value_history` ([ADR 0008](adr/0008-provenance-and-field-value-history.md))
- [ ] Link saves to `extraction_run_id` + `document_type`
- [ ] Rescan supersedes with history retained
- [ ] Profile UI: per-field source summary

### WS-5 — Form fill + attach

- [ ] Rust rules-first matcher (value + provenance per field)
- [ ] Form fill preview with confirm/cancel per field
- [ ] Form subject picker (child vs parent)
- [ ] Upload slot matcher → propose `stored_submission_document`
- [ ] Extension: inject fields + file bytes locally

### WS-6 — Expiry + share

- [ ] `dataset_health` API; form-fill guardrails
- [ ] Local expiry notifications (30d / 7d / 1d / day-of)
- [ ] Proximity share scoped field groups + TTL ([ADR 0009](adr/0009-proximity-sharing-ble-secure-channel-time-bound-grants.md))

---

## 11. Ship gates (all must pass)

### Acceptance matrix (photo E2E)

| Document | first | last | dob | ssn | dl# | dl_exp | pass# | pass_exp | carrier | member | group |
|----------|:-----:|:----:|:---:|:---:|:---:|:------:|:-----:|:--------:|:-------:|:------:|:-----:|
| Texas DL | ✅ | ✅ | ✅ | — | ✅ | ✅ | — | — | — | — | — |
| US Passport | ✅ | ✅ | ✅ | — | — | — | ✅ | ✅ | — | — | — |
| SSN card | ✅ | ✅ | — | ✅ | — | — | — | — | — | — | — |
| Insurance card | ✅ | ✅ | ✅ | — | — | — | — | — | ✅ | ✅ | ✅ |
| State ID (child) | ✅ | ✅ | ✅ | — | — | — | — | — | — | — | — |

≥ 3 distinct PNGs per row from `demo/sample-documents/household-fixtures/`.

### Submission stash + attach

- [ ] Immunization auto-save + display name
- [ ] Birth cert auto-save; no field extract
- [ ] School upload slot proposes matching stash file
- [ ] Rescan supersedes; no SQLite BLOBs
- [ ] Files encrypted at rest; zero egress

### Form automation + lineage

- [ ] Every filled field shows lineage in preview
- [ ] Expired DL/passport prompts rescan before apply
- [ ] Form write-back creates history row

### Proximity share + expiry

- [ ] Scoped share presets; TTL enforced
- [ ] Expiry notifications fire on schedule
- [ ] Zero network bytes during share (test assert)

---

## 12. Implementation branches

| Branch | Owner |
|--------|-------|
| `TrustNest_Rewrite_Sreeni` | Sreeni |
| `TrustNest_Rewrite_Gnaga` | Ganga |
| `TrustNest_Rewrite_Srikanth` | Srikanth |

Integration branch: `ganga-2026-05-16-2`

---

## 13. PR checklist (every PR)

1. Which acceptance matrix cell does this improve?  
2. Which photo fixture test proves it?  
3. Which legacy code path does this **remove**?  
4. Did any other doc type get less accurate? (run full matrix)

**Reject if:** adds orchestrator step · SQLite BLOB for scans · universal regex on unknown · form fill without lineage · extraction when `form_relevant: false`.

---

## 14. References

| Doc | Path |
|-----|------|
| Principles + Layer C detail | [fresh-start-lessons-and-principles.md](fresh-start-lessons-and-principles.md) |
| Legacy inventory | [fresh-start-implementation-baseline.md](fresh-start-implementation-baseline.md) |
| Architecture | [architecture.md](architecture.md) |
| Lineage schema | [adr/0008-provenance-and-field-value-history.md](adr/0008-provenance-and-field-value-history.md) |
| Proximity share | [adr/0009-proximity-sharing-ble-secure-channel-time-bound-grants.md](adr/0009-proximity-sharing-ble-secure-channel-time-bound-grants.md) |
| Zero egress | [trustnest-zero-egress-design-constraint.md](trustnest-zero-egress-design-constraint.md) |
| Photo corpus | `demo/sample-documents/household-fixtures/` |
| Form demo | `demo/form/demo-form.html` |

---

*TrustNest Rewrite Implementation Document v2.8 FINAL — June 2026.*
