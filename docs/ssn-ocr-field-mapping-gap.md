# SSN card OCR field-mapping gap

**Build affected:** 1.1.0 (29)  
**Fixed in:** 1.1.0 (30) — `UniversalDocumentParser` SSA stub handling

## Symptom

Scanning an SSA card stub produced incorrect mapped fields:

| Field | Wrong behavior | Expected behavior |
|-------|----------------|-------------------|
| Full name | Garbled header text (OCR misread of “SOCIAL SECURITY”) | Cardholder name line above mailing address |
| Date of birth | First bare date on document (card issue date) | Only labeled DOB/BIRTH fields; no issue date |
| SSN | Usually correct | SSN pattern extraction |
| Address | City/state/ZIP only | Street line + city/state/ZIP |

Vision OCR often captures the correct name and address in later text blocks. The failure was **classification + field mapping**, not necessarily raw text recognition.

## Root causes

### 1. Strict SSA header detection

`DocumentTypeClassifier`, `ProfileSchemaKeysForDocument`, and `UniversalDocumentParser` required the literal substring `SOCIAL SECURITY`. Vision frequently garbles the header (e.g. `LOCIAL SEOURTA` / `LOCALSECURI`), so documents were classified as `.other` and routed through generic heuristics.

### 2. Generic name heuristics on SSA layout

`UniversalDocumentParser` treated the **first plausible two-word line** as a name, which matched garbled header text before the real cardholder name. It also mapped the **first bare `MM/DD/YYYY`** to date of birth even when that date is the card issue date.

### 3. `PersonNameResolver` reinforced bad names

`resolveSSNNames` paired consecutive single-token lines from boilerplate before the real name line.

### 4. No layout label→value pairs

SSA stubs have no `Name:` / `DOB:` labels. Open-vocabulary mapping correctly reported *"No label → value pairs detected"* and fell back to broken universal heuristics.

## Fix (all in `UniversalDocumentParser`)

1. **Fuzzy SSA detection** — `looksLikeSSNDocument`: SSN pattern + stub cues (`ESTABLISHED FOR`, `YOUR SOCIAL SECURITY CARD`, garbled `LOCIAL`/`SEC*` tokens).
2. **Layout-aware SSA branch** — `parseSSAStub`: cardholder name is the line immediately above the street address (or after the instruction block), with OCR-garbage token rejection.
3. **Labeled DOB only on stubs** — issue date is never mapped to date of birth.
4. **Street + city/state/ZIP** — reuse shared address line parsers.

No separate per-document-type parser was added. Classification and `OcrFieldSuggester` route SSA stubs through `UniversalDocumentParser.parse`.

## Regression test

`UniversalDocumentParserTests.testGarbledSSAStubUsesLayoutAwareNameNotHeaderGarbage` uses synthetic fixture data only (no real PII).

## Verification

1. Install build **30+** from TestFlight.
2. Scan an SSA card stub.
3. Expect: correct cardholder name, SSN, full mailing address, **no DOB** unless a labeled birth date appears on the document.
