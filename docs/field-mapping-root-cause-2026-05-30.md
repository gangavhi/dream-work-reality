# Field mapping root cause (2026-05-30)

**Symptom:** OCR raw text on Review scan looks correct, but mapped profile fields are wrong (e.g. a person name in **Address**, dates on wrong keys, passport names scrambled).

**Status:** Implemented and verified on iOS Simulator (101 tests, May 2026).

---

## Root cause (confirmed)

Mapping is a **three-step** pipeline:

```text
OCR blocks → label/value pairs (spatial heuristics) → ONNX/bag-of-words label→profile_key → Review scan fields
```

When OCR raw is good but fields are wrong, the failure is almost always in **step 2 or 3**, not Vision OCR.

### 1. Spatial pairing treats values as labels (primary)

`OcrLayoutSerializer.isFieldLabel` previously marked **any single uppercase word** (≤24 chars) as a label — including **surnames, given names, and cities**.

**Before fix (passport layout):**

```text
Surname→SHARMA | SHARMA→PRIYA | Given Name(s)→PRIYA | PRIYA→15/03/1990
```

**After fix:**

```text
Surname→SHARMA | Given Name(s)→PRIYA | Date of Birth→15/03/1990 | Nationality→INDIAN
```

**Before fix (Texas DL-style row):**

```text
1. Name→SMITH | SMITH→JANE | 8. Address→742 OAK STREET | 742 OAK STREET→AUSTIN | AUSTIN→TX 78701
```

That produces `address_line1=AUSTIN` (city in address) or cross-row name swaps.

**After fix:**

```text
1. Name→SMITH | 8. Address→742 OAK STREET | DOB→03/15/1985 | License No→D12345678
```

→ `address_line1=742 OAK STREET`, `display_name=SMITH` (correct types).

### 2. No document-type hint for date fields

On device, classification is deferred (`classify:skipped:single_pass_parser`), so `documentTypeHint` was **nil**. Bag-of-words maps **"Date of Expiry"** to `passport_expiry` even on a driver license.

**Fix:** Infer type from OCR keywords (`TEXAS DRIVER LICENSE` → `drivers_license`) before mapping so contextual rules apply.

### 3. No value-shape validation

Even with a correct label, nothing rejected a **person name** assigned to `address_line1` or a **date** assigned to a name field.

**Fix:** `MappedFieldValueValidator` drops suggestions where value shape does not match profile key (name vs street vs date).

### 4. ONNX label mapping is not the problem

When pairs are correct, MiniLM maps labels accurately:

| Label | Mapped key |
|-------|------------|
| First Name | legal_first_name |
| 8. Address | address_line1 |
| Date of Expiry (with DL hint) | drivers_license_expiry |

Probe tests: `DreamWorkAppTests/FieldMappingRootCauseTests`.

---

## How to verify on device (build 47, no new publish)

1. Open **Review scan → OCR raw**.
2. Check **Label → value pairs**:
   - Bad: `SHARMA→PRIYA`, `742 OAK STREET→AUSTIN`, `SMITH→JANE`
   - Good: `Surname→SHARMA`, `8. Address→742 OAK STREET`
3. If pairs look good but fields still wrong → label mapping issue (check pipeline trace for `extract:semantic`).
4. If pairs look bad → spatial pairing issue (fixed locally, not in build 47).

---

## Local fixes (not in TestFlight build 47)

| File | Change |
|------|--------|
| `OcrLayoutSerializer.swift` | Stop treating single-word names/streets as labels; strip `1.` / `8.` prefixes |
| `MappedFieldValueValidator.swift` | Reject name↔address and other shape mismatches |
| `OpenVocabularyFieldExtractor.swift` | Apply value validator before accepting a suggestion |
| `ExtractionAgent.swift` | Infer document type from OCR text for contextual date/name rules |
| `SemanticFieldLabelMapper.swift` | Strip numbered field prefixes before ONNX/bag-of-words |
| `FieldMappingRootCauseTests.swift` | Regression tests for passport + DL layouts |

Run regression tests:

```bash
cd apps/ios
xcodegen generate
xcodebuild test -project DreamWorkApp.xcodeproj -scheme DreamWorkApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DreamWorkAppTests/FieldMappingRootCauseTests \
  -only-testing:DreamWorkAppTests/OcrLayoutSerializerTests
```

---

## Remaining gaps (follow-up)

- **Multi-part name rows** (`1. Name | SMITH | JANE` on one line): only `SMITH` maps today; need split-value or template extraction for first+last on same row.
- **Template extractor disabled** in orchestrator (`template:disabled:ml_only`) — coordinate-based DL template exists but is not used in production path.
- **City/state/zip** on separate lines not yet merged into address fields after pairing fix.

---

## Related doc

See also `docs/trustnest-document-field-identification-investigation.md` (2026-05-25) — same spatial-pairing diagnosis; ONNX path was added after that write-up.
