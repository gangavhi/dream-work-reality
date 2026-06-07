# TrustNest Rewrite — Implementation Document

**Status:** IMPLEMENTATION FINAL — **use this document for code**  
**Version:** 2.13  
**Repository:** [gangavhi/dream-work-reality](https://github.com/gangavhi/dream-work-reality)  
**Branches:** `ganga-2026-05-16-2` · `docs/fresh-start-principles`  
**Date:** June 2026  
**Audience:** Sreeni, Ganga, Srikanth — engineering implementation  

### Revision summary (v2.13)

| Area | Decision |
|------|----------|
| **Must-have docs** | 9 categories: Passport/ID, DL, SSN, address proof, insurance, W-2/1099/paystub, bank stmt, emergency contact, employment |
| **Raw file storage** | Preserve original format (PNG, PDF, JPEG, HEIC); no SQLite BLOBs; examples: `passport.pdf`, `license.jpg`, `insurance_card.png`, `w2.pdf` |
| **Passport extract** | Order: `full_name` (holder only) → `first_name` → `last_name` → DOB → gender → nationality → `passport_number` → issue/expiry/place/`passport_address` |
| **Passport address** | `passport_address` — as printed on passport; **not** `current_address` |
| **W-2 / 1099 / paystub** | Stash raw file ✅; field extract ❌ v1 |
| **SSN card** | Stash raw file ✅ + field extract ✅ |
| **Profile JSON** | `identity`, `contact`, `addresses[]`, `emergencyContacts[]`, nested `documents.*`, `formFillMetadata` |
| **Form fill source** | Matcher reads **Layer B** snake_case keys; profile JSON is UI/API serializer output only |

### Table of contents

1. [Product goal](#1-product-goal)  
2. [Architecture](#2-architecture-overview)  
3. [Pipeline](#3-pipeline-implement-exactly-this)  
4. [Three-layer model](#4-three-layer-data-model)  
5. [Storage](#5-storage-split-store) — split store, raw formats, must-have docs, stash whitelist  
6. [Extraction matrix](#6-auto-form-fill-extraction-matrix-mandated-documents)  
7. [Extractor registry](#7-extractor-registry)  
8. [JSON contracts](#8-json-contracts) — Layer A/C, passport spec, stash-only  
9. [Layer B + Profile schema](#9-layer-b-canonical-keys-minimum-v1) — canonical keys, profile JSON, mapping  
10. [Workstreams](#10-implementation-workstreams-single-phase)  
11. [Ship gates](#11-ship-gates-all-must-pass)  
12. [Branches](#12-implementation-branches)  
13. [PR checklist](#13-pr-checklist-every-pr)  
14. [References](#14-references)  

---

## How to use this document

| Read this | When |
|-----------|------|
| **This file** | **Primary build spec** — schema, pipeline, stash, profile JSON, extractors, gates, workstreams |
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

**Form-relevance gate (step 5):** Run Layer C extract only when `document_type` is on the extract allowlist (§6 matrix, Extract = ✅). W-2/1099/paystub: stash yes, extract no.

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
  file_extension    TEXT NOT NULL,   -- pdf | png | jpg | heic — original format preserved
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
- **Max size:** 25 MB per raw document  
- **Atomic save:** write temp → fsync → SQLite row → rename → supersede prior  

### 5.3 Raw document storage (preserve original format)

Submission stash stores the **raw document bytes in the original format** — no forced conversion. A scanned PNG stays PNG; an imported PDF stays PDF; a camera HEIC stays HEIC. Encryption (`.enc`) wraps the original file; decrypt at form attach yields the same `mime_type` the vendor upload expects.

**Supported raw formats (v1):**

| Extension | MIME type | Typical source |
|-----------|-----------|----------------|
| `.png` | `image/png` | Screenshot, photo import, simulator fixtures |
| `.jpg` / `.jpeg` | `image/jpeg` | Camera, photo library |
| `.heic` | `image/heic` | iOS camera (default) |
| `.pdf` | `application/pdf` | File import, email attachment, multi-page scan |

**Capture / import paths:**

| Source | Raw format preserved |
|--------|---------------------|
| Camera scan | HEIC or JPEG (device default) |
| Photo library pick | Original asset format (JPEG, PNG, HEIC) |
| Files / share sheet import | PDF, PNG, JPEG as provided |
| Paste / drag (desktop extension) | As provided |

**Rules:**

- Record `mime_type` + infer `file_extension` on save — form attach sets browser `File` type from `mime_type`.
- **Do not** normalize all scans to PNG or PDF — vendors accept mixed types; conversion loses quality and breaks multi-page PDFs.
- **Do not** store raw bytes in SQLite — filesystem + `stored_submission_document.file_path` only.
- Non-stash scans: raw bytes released after OCR; only `extraction_run` JSON persists.
- Stash-listed scans: raw bytes encrypted to `submission_docs/{person}/{type}/current.enc`.

**Example imports (mixed formats — each kept as-is):**

| User file | `document_type` | Stash raw file? | Field extract? | `mime_type` | `file_extension` |
|-----------|-----------------|:---------------:|:--------------:|-------------|------------------|
| `passport.pdf` | `passport` | ✅ | ✅ | `application/pdf` | `pdf` |
| `license.jpg` | `driversLicense` | ✅ | ✅ | `image/jpeg` | `jpg` |
| `insurance_card.png` | `insuranceCard` | ✅ | ✅ | `image/png` | `png` |
| `w2.pdf` | `w2` | ✅ | ❌ | `application/pdf` | `pdf` |

`w2.pdf` / `1099` / pay stub: **stash raw file** (must-have category); **no field extract** in v1 — `extractedFields: {}`; OCR JSON in `extraction_run` only.

On disk, bytes live in `{uuid}.enc` under `submission_docs/` — not as `passport.pdf`. `mime_type` + `file_extension` record the original format so form attach presents `passport.pdf` (or equivalent) to the vendor upload field.

### 5.4 Must-have documents (household baseline)

Every household profile must support these **nine categories**. Scannable types auto-stash the raw file (PNG, PDF, JPEG, HEIC) in original format.

| ✓ | Category | `document_type`(s) | Stash raw file | Field extract (v1) | Profile / Layer B |
|---|----------|-------------------|:--------------:|:------------------:|-------------------|
| ✓ | **Passport / ID** | `passport`, `stateId` | ✅ | ✅ | `identity`, `documents.passport` |
| ✓ | **Driver License** | `driversLicense` | ✅ | ✅ | `documents.driversLicense` |
| ✓ | **SSN Card** | `ssnCard` | ✅ | ✅ | `identity.ssn` / `ssnLast4`, `documents.ssnCard` |
| ✓ | **Address Proof** | `utility_bill`, `lease` | ✅ | ✅ | `addresses[]`, `documents.addressProof[]` |
| ✓ | **Insurance Card** | `insuranceCard` | ✅ | ✅ | `documents.insurance` |
| ✓ | **W-2 / 1099 / Pay stub** | `w2`, `form1099`, `payStub` | ✅ | ❌ | `documents.w2[]`, `form1099[]`, `paystub[]` (stash; extract future) |
| ✓ | **Bank Statement** | `bankStatement` | ✅ | partial | `addresses[]`, `documents.bankStatements[]` |
| ✓ | **Emergency Contact** | — | — | manual | `emergencyContacts[]` — manual or form write-back |
| ✓ | **Employment Information** | — | — | manual | `documents.employment` — manual or form write-back |

**Baseline import examples:** `passport.pdf` · `license.jpg` · `insurance_card.png` · `w2.pdf` (plus utility bill, SSN card scan, bank statement PDF as needed).

**Completeness UX:** Profile shows checklist per person — ✓ when category has confirmed fields and/or a current `stored_submission_document` (or manual entry for emergency / employment).

**Raw file link:** Encrypted originals (`passport.pdf`, `license.jpg`, …) persist in `stored_submission_document` and link to the matching `profile.documents.*` section by `document_type`. Form attach reads stash rows directly — not the profile JSON.

**Optional v1.1:** TIFF (`image/tiff`), WebP (`image/webp`) if import demand appears — same pointer + encrypt pattern.

### 5.5 Submission stash whitelist (pipeline step 4)

If `document_type` is in this list → **always** encrypt raw bytes + insert `stored_submission_document` before user leaves scan review (when auto-save setting is on).

```text
passport, stateId, driversLicense, ssnCard,
utility_bill, utilityBill, lease,
insuranceCard, bankStatement,
w2, form1099, payStub,
immunizationRecord, birthCertificate
```

**Not on whitelist** (release bytes after OCR): `unknown`, receipts, `taxReturn`, `marriageCertificate`, medical records, `transcript`, `degree`, `studentId`, `emergencyContact`, …

**Stash gate pseudocode:**

```text
fn should_stash(document_type) -> bool:
    return document_type in STASH_WHITELIST

fn on_scan_complete(type, raw_bytes, mime_type):
    save extraction_run OCR JSON
    if should_stash(type):
        encrypt raw_bytes → stored_submission_document  // preserve mime_type + file_extension
    else:
        drop raw_bytes
    if form_relevant(type):
        run Layer C extractor
```

---

## 6. Auto form fill extraction matrix (mandated documents)

What each document contributes to **typed field auto-fill** vs **file stash**.

| Document | Extract | Stash | Layer B fields | Typical USA forms |
|----------|:-------:|:-----:|----------------|-------------------|
| **Passport** | ✅ | ✅ | `full_name`, `first_name`, `last_name`, `date_of_birth`, `gender`, `nationality`, `passport_number`, `passport_expiry`, `passport_issue_date`, `passport_issued_place`, `passport_address` | Travel, I-9, school ID |
| **Driver’s license** | ✅ | ✅ | `first_name`, `last_name`, `date_of_birth`, `driver_license_number`, `driver_license_state`, `driver_license_expiry`, `current_address` | School, medical, rental |
| **State ID** | ✅ | ✅ | `first_name`, `last_name`, `date_of_birth`, `state_id_number`, `state_id_expiry` | Child school forms |
| **SSN card** | ✅ | ✅ | `first_name`, `last_name`, `ssn` | Benefits, I-9 |
| **Insurance card** | ✅ | ✅ | `first_name`, `last_name`, `date_of_birth`, `insurance_provider`, `policy_number`, `insurance_group_id` | Medical, school nurse |
| **Utility bill** | ✅ | ✅ | `full_name` (opt), `current_address` | School proof of residence |
| **Lease** | ✅ | ✅ | `first_name`, `last_name`, `current_address` | School district, rental |
| **Bank statement** | ✅ | ✅ | `current_address`, `mailing_address`, `bank_account_number`, `routing_number` | Direct deposit, address proof |
| **Immunization record** | ✅ | ✅ | `first_name`, `vaccination_status[]` | School health vaccine table |
| **Visa / EAD / I-94** | ✅ | ❌ | name, `visa_number` or `work_authorization_number`, expiry | Immigration, I-9 |
| **Birth certificate** | ❌ | ✅ | — | School **upload only** |
| **W-2 / 1099 / pay stub** | ❌ | ✅ | — (stash only v1) | Loan, benefits, tax upload attach |

**Ship priority (photo E2E):** Texas DL → SSN card → insurance card → passport → child state ID.

---

## 7. Extractor registry

| `document_type` | Extractor | Primary OCR anchors |
|-----------------|-----------|---------------------|
| `driversLicense` | `TexasDriverLicenseExtractor` | AAMVA barcode; `4d. DL`; `3. DOB`; `8.` address |
| `passport` | `PassportExtractor` | MRZ TD3; biodata `Date of issue`, `Authority` / `Place of issue`, any address line(s) on biodata |
| `ssnCard` | `SSNCardExtractor` | `###-##-####`; name above address |
| `insuranceCard` | `InsuranceCardExtractor` | `MEMBER ID`, `GROUP`, `SUBSCRIBER` |
| `stateId` | `StateIdExtractor` | `STATE ID`, `DOB:`, `ID:` |
| `utilityBill`, `lease` | `AddressProofExtractor` | service address block |
| `bankStatement` | `BankStatementExtractor` | mailing block, routing, account |
| `immunizationRecord` | `ImmunizationRecordExtractor` | vaccine row table |
| `visa`, `workAuthorization`, `immigrationForm` | `ImmigrationDocumentExtractor` | auth #, expiry |
| `w2`, `form1099`, `payStub` | **none** | must-have **stash only** (no extract v1) |
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
    "first_name": "John",
    "last_name": "Doe",
    "date_of_birth": "1990-01-01",
    "gender": "M",
    "nationality": "USA",
    "passport_number": "X1234567",
    "issue_date": "2022-05-01",
    "issued_place": "United States Department of State",
    "address": "123 Main St, Austin, TX 78701",
    "expiry_date": "2032-05-01"
  }
}
```

**Field order (passport extract):** `full_name` (holder only) → `first_name`, `last_name` → `date_of_birth` → `gender` → `nationality` → `passport_number` → issue/expiry/place/address.

**Holder-name rule:** `full_name`, `first_name`, and `last_name` must come from the passport **holder** biodata/MRZ block only — not parents, emergency contacts, endorsements, or issuer names.

Map `expiry_date` → `passport_expiry`, `issue_date` → `passport_issue_date`, `issued_place` → `passport_issued_place`, `address` → `passport_address` on save. Do **not** map passport address to `current_address`. Split `full_name` into `first_name` + `last_name` when biodata uses separate `Given names` / `Surname` lines.

### 8.1 Passport extractor spec (`PassportExtractor`)

**Extraction sequence (mandated):** `full_name` → `first_name` → `last_name` → `date_of_birth` → `gender` → `nationality` → `passport_number` → `passport_expiry` → `passport_issue_date` → `passport_issued_place` → `passport_address`.

**Holder-name rule:** Name fields come from passport **holder** biodata/MRZ only — never parent, emergency contact, endorsement, or issuer text.

| Layer B key | OCR anchor | Source | Notes |
|-------------|------------|--------|-------|
| `full_name` | MRZ holder / biodata name block | `VERIFIED` / `HIGH` | First in sequence; holder only |
| `first_name` | MRZ given names / `Given names` | `VERIFIED` | |
| `last_name` | MRZ surname / `Surname` | `VERIFIED` | |
| `date_of_birth` | MRZ DOB `YYMMDD` | `VERIFIED` | ISO date on save |
| `gender` | MRZ sex / biodata `Sex` | `VERIFIED` | `M` / `F` / `X` |
| `nationality` | MRZ country / `Nationality` | `VERIFIED` | |
| `passport_number` | MRZ doc # / `Passport No.` | `VERIFIED` | |
| `passport_expiry` | MRZ expiry | `VERIFIED` | Expiry guardrails |
| `passport_issue_date` | `Date of issue` | `HIGH` | |
| `passport_issued_place` | `Place of issue` / `Authority` | `HIGH` | |
| `passport_address` | Address line(s) on biodata | `HIGH` | As printed; **not** `current_address` |

| `extracted_fields` key | Layer B key |
|------------------------|-------------|
| `full_name` | `full_name` |
| `first_name` | `first_name` |
| `last_name` | `last_name` |
| `date_of_birth` | `date_of_birth` |
| `gender` | `gender` |
| `nationality` | `nationality` |
| `passport_number` | `passport_number` |
| `expiry_date` | `passport_expiry` |
| `issue_date` | `passport_issue_date` |
| `issued_place` | `passport_issued_place` |
| `address` | `passport_address` |

### 8.2 Stash-only JSON (no field extract)

**Birth certificate:**

```json
{
  "document_type": "birthCertificate",
  "confidence": 0.91,
  "form_relevant": false,
  "extracted_fields": null,
  "submission_doc_id": "uuid-of-saved-file"
}
```

**W-2 / 1099 / pay stub (must-have — stash only v1):**

```json
{
  "document_type": "w2",
  "confidence": 0.93,
  "form_relevant": false,
  "extracted_fields": null,
  "submission_doc_id": "uuid-of-saved-file"
}
```

Raw file (`w2.pdf`) encrypted on disk; `documents.w2[]` in profile stays empty until W-2 field extract ships.

---

## 9. Layer B canonical keys (minimum v1)

```text
# Identity
full_name, first_name, last_name, middle_name, date_of_birth, place_of_birth, gender, nationality, marital_status

# Government IDs
ssn, passport_number, passport_expiry, passport_issue_date, passport_issued_place, passport_address,
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

# Family / emergency / employment (manual or form write-back v1)
emergency_contacts[]   # { name, relationship, phone, email, address }
employer_name, job_title, employment_status, hire_date, salary, hourly_rate
```

**Legacy renames:** `insurance_carrier` → `insurance_provider` · `insurance_member_id` → `policy_number` · `drivers_license_*` → `driver_license_*`

**Storage rule:** Layer B = flat `field_value_current` keyed by person + canonical key. Profile JSON (§9) = **read model** built by serializer — never the write path for form fill.

### Profile JSON schema (UI / API view)

Layer B is stored flat in SQLite (`field_value_current`). The **profile** is the grouped, UI-facing view per person. Serializers map Layer B + confirmed extraction into this shape.

```json
{
  "profile": {
    "identity": {
      "firstName": "",
      "middleName": "",
      "lastName": "",
      "fullLegalName": "",
      "dateOfBirth": "",
      "placeOfBirth": "",
      "gender": "",
      "citizenship": "",
      "maritalStatus": "",
      "ssn": "",
      "ssnLast4": ""
    },
    "contact": {
      "primaryPhone": "",
      "secondaryPhone": "",
      "email": ""
    },
    "addresses": [
      {
        "addressType": "current",
        "street1": "",
        "street2": "",
        "city": "",
        "state": "",
        "zipCode": "",
        "country": "",
        "moveInDate": "",
        "moveOutDate": ""
      }
    ],
    "emergencyContacts": [
      {
        "fullName": "",
        "relationship": "",
        "phone": "",
        "email": "",
        "address": ""
      }
    ],
    "documents": {
      "passport": {
        "documentNumber": "",
        "country": "",
        "nationality": "",
        "issueDate": "",
        "expirationDate": "",
        "placeOfIssue": "",
        "issuingAuthority": "",
        "mrzData": "",
        "photoAvailable": true
      },
      "driversLicense": {
        "licenseNumber": "",
        "state": "",
        "class": "",
        "issueDate": "",
        "expirationDate": "",
        "restrictions": "",
        "endorsements": "",
        "addressOnLicense": "",
        "realId": true
      },
      "ssnCard": {
        "fullSSN": "",
        "nameOnCard": "",
        "issueKnown": false
      },
      "addressProof": [
        {
          "documentType": "",
          "provider": "",
          "accountNumberMasked": "",
          "serviceAddress": "",
          "statementDate": "",
          "billingPeriod": ""
        }
      ],
      "insurance": {
        "insuranceType": "",
        "providerName": "",
        "memberId": "",
        "groupNumber": "",
        "policyNumber": "",
        "subscriberName": "",
        "subscriberDOB": "",
        "effectiveDate": "",
        "expirationDate": "",
        "copay": "",
        "rxBin": "",
        "rxPcn": ""
      },
      "w2": [
        {
          "taxYear": "",
          "employerName": "",
          "employerEIN": "",
          "employeeName": "",
          "employeeSSN": "",
          "wages": "",
          "federalTaxWithheld": "",
          "state": "",
          "stateWages": "",
          "stateTax": ""
        }
      ],
      "form1099": [
        {
          "taxYear": "",
          "payerName": "",
          "payerTIN": "",
          "recipientTIN": "",
          "incomeType": "",
          "grossAmount": "",
          "federalTaxWithheld": ""
        }
      ],
      "paystub": [
        {
          "employerName": "",
          "employeeId": "",
          "payPeriodStart": "",
          "payPeriodEnd": "",
          "grossPay": "",
          "netPay": "",
          "taxes": "",
          "deductions": "",
          "ytdGross": "",
          "ytdNet": ""
        }
      ],
      "bankStatements": [
        {
          "bankName": "",
          "accountType": "",
          "accountNumberMasked": "",
          "routingNumber": "",
          "statementStartDate": "",
          "statementEndDate": "",
          "averageBalance": "",
          "endingBalance": ""
        }
      ],
      "employment": {
        "employmentStatus": "",
        "employerName": "",
        "jobTitle": "",
        "department": "",
        "employeeId": "",
        "employmentType": "",
        "workEmail": "",
        "workPhone": "",
        "salary": "",
        "hourlyRate": "",
        "hireDate": "",
        "managerName": "",
        "workAddress": ""
      }
    },
    "formFillMetadata": {
      "preferredFirstName": "",
      "preferredLanguage": "",
      "signatureStored": false,
      "defaultAddressId": "",
      "defaultPhone": "",
      "defaultEmail": ""
    }
  }
}
```

**v1 ship scope:** All [must-have document categories](#54-must-have-documents-household-baseline). Field extract populates `identity`, `addresses`, and `documents.*` where Layer C ships; W-2/1099/paystub arrays start empty (stash raw file only). **Raw encrypted files** (`passport.pdf`, `license.jpg`, …) live in `stored_submission_document` — linked by `document_type`, not duplicated in this JSON.

#### Layer B → profile mapping

| Layer B canonical key | Profile path | Notes |
|-----------------------|--------------|-------|
| `full_name` | `identity.fullLegalName` | Holder only — never parent, emergency contact, or issuer |
| `first_name` | `identity.firstName` | |
| `last_name` | `identity.lastName` | |
| *(parse)* | `identity.middleName` | From passport given names / manual |
| `date_of_birth` | `identity.dateOfBirth` | ISO `YYYY-MM-DD` |
| `ssn` | `identity.ssn`, `identity.ssnLast4` | Full SSN in profile vault (encrypted at rest); last-4 for display |
| `gender` | `identity.gender` | |
| `nationality` | `identity.citizenship`, `documents.passport.nationality` | |
| `marital_status` | `identity.maritalStatus` | Manual / form write-back |
| `email` | `contact.email`, `formFillMetadata.defaultEmail` | |
| `phone_number` | `contact.primaryPhone`, `formFillMetadata.defaultPhone` | |
| `current_address` | `addresses[addressType=current]` | Parse `street1` / `city` / `state` / `zipCode` |
| `mailing_address` | `addresses[addressType=mailing]` | When present |
| `passport_number` | `documents.passport.documentNumber` | |
| `passport_issue_date` | `documents.passport.issueDate` | |
| `passport_expiry` | `documents.passport.expirationDate` | |
| `passport_issued_place` | `documents.passport.placeOfIssue` | |
| `passport_issued_place` (authority line) | `documents.passport.issuingAuthority` | When biodata has separate authority |
| `passport_address` | Layer B only (v1) | As printed on passport — not `addresses[current]` |
| `nationality` (country code) | `documents.passport.country` | ISO country of document |
| `driver_license_number` | `documents.driversLicense.licenseNumber` | |
| `driver_license_state` | `documents.driversLicense.state` | |
| `driver_license_expiry` | `documents.driversLicense.expirationDate` | |
| `current_address` (from DL) | `documents.driversLicense.addressOnLicense` | |
| `state_id_number` | `identity` + ID fields TBD | v1: stash `stateId` scan; populate `identity.firstName/lastName/DOB`; add `documents.stateId` in v1.1 if needed |
| `ssn` (from card) | `documents.ssnCard.fullSSN`, `identity.ssn` | |
| `full_name` (from card) | `documents.ssnCard.nameOnCard` | |
| `current_address` (utility/lease) | `documents.addressProof[].serviceAddress` | + `addresses[]` |
| `insurance_provider` | `documents.insurance.providerName` | |
| `policy_number` | `documents.insurance.memberId`, `policyNumber` | |
| `insurance_group_id` | `documents.insurance.groupNumber` | |
| `bank_account_number` | `documents.bankStatements[].accountNumberMasked` | Last-4 / masked |
| `routing_number` | `documents.bankStatements[].routingNumber` | |
| `emergency_contacts[]` | `emergencyContacts[]` | Manual / form write-back |
| `employer_name`, etc. | `documents.employment`, `documents.w2[]` | Manual v1; W-2 extract → `w2[]` future |
| `stored_submission_document` | *(implementation)* | Raw PNG/PDF/JPEG/HEIC on disk; form attach uses stash row by `document_type` |

#### Passport → profile (example)

After confirmed passport scan (`passport.pdf` stashed + fields extracted):

```json
{
  "identity": {
    "firstName": "John",
    "lastName": "Doe",
    "fullLegalName": "John Doe",
    "dateOfBirth": "1990-01-01",
    "gender": "M",
    "citizenship": "USA"
  },
  "documents": {
    "passport": {
      "documentNumber": "X1234567",
      "country": "USA",
      "nationality": "USA",
      "issueDate": "2022-05-01",
      "expirationDate": "2032-05-01",
      "placeOfIssue": "United States",
      "issuingAuthority": "United States Department of State",
      "photoAvailable": true
    }
  }
}
```

**Rules:**

- **Form matcher reads Layer B keys** (snake_case), not camelCase profile paths.
- `profile.documents.*` = confirmed typed field groups per document type.
- **Raw files** = `stored_submission_document` + encrypted `.enc` on disk (original format preserved).
- `formFillMetadata` = user preferences for form automation — not from document extraction.

### 9.1 Profile serializer (implement)

| Component | Owner | Responsibility |
|-----------|-------|----------------|
| `ProfileSerializer` | Rust FFI | Read `field_value_current` + `stored_submission_document` → emit profile JSON |
| `ProfileDeserializer` | Rust FFI | Manual edits / form write-back → Layer B keys + history |
| Must-have checklist UI | Swift | 9 categories; ✓ when stash row and/or fields present |
| Form matcher | Rust | **Only** Layer B keys — ignore camelCase profile paths |

**Serializer flow:**

```text
field_value_current (person_id) → map via §9 table → profile.identity / documents.*
stored_submission_document (person_id, is_current) → link by document_type (not embedded in profile JSON)
emergency_contacts[], employment → Layer B manual keys → profile sections
```

**Baseline E2E fixtures** (`demo/sample-documents/household-fixtures/`):

| File | Expect after scan |
|------|-------------------|
| `passport.pdf` | Stash row + `documents.passport.*` + `identity.*` populated |
| `license.jpg` | Stash row + `documents.driversLicense.*` populated |
| `insurance_card.png` | Stash row + `documents.insurance.*` populated |
| `w2.pdf` | Stash row only; `documents.w2[]` empty v1 |

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

- [ ] Swift `SubmissionDocumentStore` — encrypt/write/read `.enc`; preserve `mime_type` + `file_extension`
- [ ] Rust `stored_submission_document` CRUD + supersede
- [ ] Stash whitelist (§5.5) enforced in pipeline step 4
- [ ] Auto-save on stash-listed scan; settings toggle
- [ ] Must-have checklist UI (9 categories)
- [ ] Baseline fixtures: `passport.pdf`, `license.jpg`, `insurance_card.png`, `w2.pdf`

### WS-4 — Vault + lineage + profile (Rust)

- [ ] `field_value_current` + `field_value_history` ([ADR 0008](adr/0008-provenance-and-field-value-history.md))
- [ ] Link saves to `extraction_run_id` + `document_type`
- [ ] Rescan supersedes with history retained
- [ ] `ProfileSerializer` / `ProfileDeserializer` (§9.1)
- [ ] Profile UI: per-field source summary + must-have checklist

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

**Passport extended fields (photo E2E):** `passport_issue_date`, `passport_issued_place`, `passport_address` must populate from US passport fixture when labels present.
| SSN card | ✅ | ✅ | — | ✅ | — | — | — | — | — | — | — |
| Insurance card | ✅ | ✅ | ✅ | — | — | — | — | — | ✅ | ✅ | ✅ |
| State ID (child) | ✅ | ✅ | ✅ | — | — | — | — | — | — | — | — |

≥ 3 distinct PNGs per row from `demo/sample-documents/household-fixtures/`.

### Must-have documents (9 categories)

- [ ] Passport/ID, DL, SSN card, address proof, insurance, W-2/1099/paystub, bank statement — scan → stash raw file (original format)
- [ ] Emergency contact + employment — manual entry or form write-back; profile checklist shows ✓
- [ ] Baseline fixtures: `passport.pdf`, `license.jpg`, `insurance_card.png`, `w2.pdf` all persist to `stored_submission_document` + populate `documents.*` where extract ships

### Submission stash + attach

- [ ] Immunization auto-save + display name
- [ ] Birth cert auto-save; no field extract
- [ ] W-2/1099/paystub auto-save; no field extract (stash only)
- [ ] SSN card auto-save + field extract
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

*TrustNest Rewrite Implementation Document v2.13 FINAL — June 2026. Build from this file; principles detail in [fresh-start-lessons-and-principles.md](fresh-start-lessons-and-principles.md).*
