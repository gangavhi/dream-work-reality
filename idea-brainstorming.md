# Idea brainstorming: Dream Work Reality

This document captures an open-ended exploration of the product concept: a **local-first** application that uses **OCR** to extract structured information about people and families, stores it **on-device** in a relational database, and helps users **complete online forms** using that data—with optional review, support for **OTP-heavy** flows, and explicit control over **what (if anything)** crosses a **network boundary**. It also covers **offline, selective sharing** of structured memory with trusted devices (household members) for **bounded time**, without routing that payload over the **internet**.

---

## 1. Core thesis

**Users repeatedly re-enter the same sensitive information** (identity, household, employment, benefits, healthcare, education) across fragmented web forms. Meanwhile they are asked to **trust** cloud services, aggregators, or browser extensions with data that is hard to revoke and easy to misuse.

**Thesis:** A tool that keeps **canonical personal and family data under the user’s control** on their own hardware—while still making multi-step and OTP-gated forms tractable—addresses a real tension between **convenience** and **privacy**.

---

## 2. Problem statement (expanded)

### 2.1 Who feels the pain?

- **Parents and caregivers** managing dependents across schools, insurance, and government portals.
- **People in life transitions** (moving, marriage, job change) who file many forms in a short window.
- **Anyone sensitive to data centralization** (security-conscious users, professionals handling regulated data).
- **Users in markets** where mobile-first access to services is normal but desktop “password manager + spreadsheet” workflows fail.

### 2.2 What is broken today?

| Gap | Description |
|-----|-------------|
| **Re-entry fatigue** | Same fields typed dozens of times; copy-paste across devices breaks formatting. |
| **Context switching** | Finding the right document (PDF, photo, email) while a session timer runs. |
| **Trust asymmetry** | Forms demand data; users rarely get portability, deletion, or transparency. |
| **Extension / cloud risk** | Autofill products often sync secrets or page content to servers by design. |
| **OCR is disconnected** | Scanning apps produce files, not structured fields tied to “this is my child’s immunization record.” |

### 2.3 What “success” looks like for the user

- **One place** to see and edit “our household’s facts” with clear ownership (which person, which document).
- **Faster** form completion with **review** when stakes are high, **speed** when they are not—**in the user’s real browser (Chrome + extension)** on desktop/tablet/phone, and **inside other apps** on tablet/phone where supported.
- **OTP and multi-step flows** that remain inside a controlled session the user understands.
- **No surprise uploads** of family PII to a vendor backend.
- **Controlled sharing inside the household**: another caregiver or partner can receive **only the fields they need**, **only until** an agreed deadline, via **proximity transfer**—not via cloud sync.

---

## 3. Product pillars (brainstorm)

### 3.1 Local-first data plane

- **OCR** turns unstructured captures into **candidates**; the user (or rules) **confirms** structure before it becomes “truth” in the DB.
- **Two complementary ways to bring a document in** (both processed **on-device**; neither path sends raw document content to your backend):
  - **On-the-fly scan** — The user points the camera at a physical document **in the moment** (wallet card, letter, form on a desk). The app captures one or more pages, optionally with guidance (alignment, corners, lighting) so the image is readable before OCR runs. Suited to “I have it in front of me right now” and to **quick capture during a form** without switching to another app.
  - **Upload** — The user picks an **existing** photo from the gallery, or a **file** from storage (PDF, image—where the platform allows), often for “I already have a picture” or laptop workflows.
- **RDBMS on device** enables relationships: person ↔ address ↔ employer ↔ dependent ↔ document metadata.
- **Provenance**: optional trail (“this field came from OCR of document X on date Y”) to support corrections and trust, including whether the source was **live scan** vs **upload**.
- **Optional retained scans (for upload-heavy forms):** For categories the user marks as important—**driver license**, **passport / government photo ID**, **vaccination or immunization records**, **insurance cards**, and similar—the product can **keep an encrypted copy of the scan or file** on device (image or PDF, per platform), **not only** the extracted text fields. The user **decides per document type or per capture** whether to **store the file**, **fields only**, or **both**, so they can satisfy **“attach a scan”** or **“upload proof”** requirements without re-photographing each time. When a **new** scan supersedes an old one (e.g. renewed license), retention policy aligns with **§3.7** (replace file, keep history link if product allows).

### 3.2 Form assistant (experience plane): three scenarios by device

Form filling is **not** one implementation everywhere. The same **local memory** powers three coordinated scenarios:

| Scenario | Where the user fills the form | Primary mechanism |
|----------|-------------------------------|-------------------|
| **A — Desktop / laptop** | **System browser** (Chrome first; other Chromium browsers may follow) | **Browser extension** (“add-on”) that talks to the **companion app** holding local memory. User browses the web as usual. |
| **B — Tablet** | **Chrome** (same as A) **or** **another app** that contains a form (banking app, benefits app, etc.) | **Extension + companion app** for Chrome; **additional surface** for in-app forms (accessibility / platform APIs or assisted overlay—product-defined) so structured data can still be applied **without** uploading it. |
| **C — Mobile phone** | **Chrome** (same as A) **or** **another app** with a form | Same split as tablet: **extension path** in Chrome; **in-app form path** for third-party apps. |

**Installation flow (browser path):** The user installs the **browser extension** (e.g. for Chrome). That step **also** installs or updates the **compatible companion application** in the background (or triggers a one-time install prompt), so the extension has a **local, privileged partner** to read structured memory—**never** a remote copy of household data.

**Form detection (browser path):** The extension **determines whether the active page is a form** (inputs, semantics, heuristics). **Only when** a form is detected should it offer **assisted filling** from local memory and **next steps** (review, field-by-field apply, submit guidance). On **non-form pages** it stays **idle**—no injection, no noisy UI.

**Coexistence with the browser’s own autofill:** If the user relies on **Chrome’s built-in autofill** (or password manager autofill), the platform **must not fight it**: no competing automatic fills, no stealing focus from native suggestions. Assisted filling activates when the **user explicitly invokes** the platform (toolbar, shortcut, or clear in-page affordance—product-defined), or when policy allows **gentle** non-conflicting hints—**never** by overwriting native behavior silently.

**Embedded in-app browser (optional):** A URL opened **inside** the companion app remains a **valid alternative** for users who prefer not to use Chrome; same review / fast-path modes apply there.

**Field mapping** connects local schema fields to page inputs (heuristics + saved per-site overrides + user nudges) in **whichever** surface is active (extension DOM, in-app WebView, or in-app native form mapping).

**Which household member is this form for?** Every assisted fill session must be scoped to **one** household **profile** at a time (self, spouse/partner, each child, or any other member the user has defined)—so the right names, IDs, and document-linked fields are used. The product should:

- **Prefer asking** rather than guessing when unsure: a clear chooser—e.g. **“This form is for…”** with **Me**, **My partner**, and **each child** (by name), plus **Other household member** if applicable.
- **Use light hints** only when confidence is high (e.g. page title or labels contain a dependent’s first name that uniquely matches one profile, or the user previously saved a **per-site default** such as “this school portal is always for Alex”). Hints never **auto-switch** profile without confirmation if multiple children share similar labels.
- Show an **obvious, persistent indicator** during the session—**“Filling for: [Name]”—** with **Change** so the user can fix a mistake before anything sensitive is applied.
- Scope **gap detection**, **save / update prompts**, and **retained document attachments** to the **active** profile unless the user changes it.

**File-upload fields:** When a form expects an **attachment** (PDF, JPG of ID, etc.), the companion app or helper can offer **“Attach from saved documents”** for types the user has retained locally—subject to format/size limits of the website—so structured fill and **proof upload** stay in one workflow **without** sending files to your backend first.

**Modes** (all surfaces where applicable):

- **Review then submit**: diff/preview, inline edits, then submit.
- **Fast path**: fill and submit with minimal friction (where policy allows).

### 3.3 OTP and “last mile” flows

- Many critical forms end with **SMS or email OTP**. The product should treat OTP as **user-completed inside the same session** (browser tab or third-party app), not as something to “solve” server-side.
- UX focus: **visibility** (where is the OTP field?), **timeouts**, **resend**, **error text**—reducing abandonment without exfiltrating codes.

### 3.4 Ephemeral vs persistent edits; gaps in local memory

The local database must support **both**:

- **Updating** values that **already exist** in memory when the user changes them on the form and confirms they want local memory to match.
- **Adding** values for fields that were **missing** before this session, when the user confirms they should be kept.

**Updates (write-back to existing fields):** During review—or after editing inline on the page—the user may correct **pre-filled** information (wrong phone, new address, updated grade). The app asks whether to **update saved information** in local memory—e.g. **“Replace what we had on file with what you entered?”** — **Yes / No / Decide later**. **Yes** **overwrites** the current stored value for that logical field (subject to **§3.7** history rules: prior value may move to **effective-until** trail), not merely duplicating a new row without link to the old fact.

**Adds (new fields or first-time values):** Before or during apply, the product compares **what the form needs** with **what exists in local memory** for the selected person or context. When **gaps** exist—fields with no value, or never-captured attributes—the user should be **prompted clearly** to **enter the missing information** (inline, checklist, or field-by-field—product-defined), not left with silent empty boxes.

After the user **supplies** missing values (typed, pasted, or brought in via scan/upload in-session), the app asks whether those **new** values should be **stored in local memory for future forms**—same consent pattern as updates: **Yes / No / Decide later**, with **sensitive-field** policies (e.g. extra confirmation for government IDs) so storage is **conscious**, not accidental.

**Important:** The product is **not** “append-only.” Persisting from a form session means **authoritative sync** of the user’s chosen values into the relational store—**insert** where empty, **update** where something was already stored—when the user agrees.

This turns every form session into an optional **feedback loop** that improves local data quality **without** a cloud training pipeline.

### 3.5 Remote surface (minimal by design)

- **Account layer only**: registration, login, logout, password reset, device/session management as needed.
- **Optional anonymous telemetry**: e.g. session success/failure, latency buckets—**no field values**, no OCR text.

### 3.6 Offline selective sharing (“AirDrop-class” proximity transfer)

Households often have **multiple people** and **multiple devices**, but the same privacy bar: **no central repository of family PII**. This pillar adds a **robust, optional** way to move **structured local memory** to another device **without using the internet** for that payload—analogous in *intent* to **AirDrop** / **Nearby Share** / **Quick Share**, but **semantically aware** (field-level grants, time windows, household roles).

#### 3.6.1 What problem it solves

| Need | How this feature helps |
|------|-------------------------|
| Partner completes forms while primary keeper holds the documents | Share **only** the derived fields (e.g. child’s school info), not the whole vault. |
| Temporary help (e.g. visiting relative) | **Expiry**: access ends automatically after a date/time or duration. |
| Principle of least privilege | **Who** can see **which** person’s **which** attributes is explicit and auditable on the sender’s device. |
| No cloud “family sync” | Transfer uses **local wireless proximity** (see below), not your product’s backend as a data pipe. |

#### 3.6.2 What “does not involve data leaving via internet” means (precisely)

- **Payload path:** Encrypted structured export travels over **peer-to-peer local radio** (e.g. Wi-Fi Direct, AWDL-style direct link, Bluetooth LE for discovery + negotiated high-throughput channel, UWB-assisted pairing where available)—**not** over HTTPS to a server for delivery.
- **Out of scope for this claim:** The **recipient device** may still use cellular/Wi-Fi for unrelated traffic; marketing copy should say **“shared payload does not traverse the internet”** or **“device-to-device transfer without cloud relay”** to avoid overclaiming “the phone had no network.”
- **Backend:** Account services remain **orthogonal**; sharing does not require uploading shared content to your API.

#### 3.6.3 Household policy model (who sees what, until when)

Think in terms of **grants**, not copies without rules:

- **Grantor:** The household member (or device profile) that authorizes export.
- **Grantee:** A **named household role** or **trusted device identity** (e.g. “Mom’s phone,” “Dad’s tablet”) established out-of-band (QR pairing, short code in same room, or first-time physical proximity enrollment).
- **Scope:** 
  - **Subject:** which **Person** records (self, child, dependent).
  - **Field groups:** e.g. **demographics**, **contact**, **school**, **insurance identifiers**—or finer-grained **field-level** toggles for high-sensitivity columns.
  - **Documents:** whether to include **OCR-derived fields only**, **retained scan files** for specific types (explicit opt-in per grant), or also **redacted previews** / metadata (never silent full-image blast by default).
- **Temporal bound:** 
  - **Valid until** (absolute timestamp), or **duration** (e.g. 48 hours), with **revocation** from grantor’s device at any time.
  - Recipient app **enforces expiry locally** (data becomes unusable / auto-deleted per policy); clocks and tampering are a known limitation (see `devils-advocate.md`).

#### 3.6.4 User experience (sketch)

1. **Share sheet:** “Share structured data…” → pick **people** and **field bundles** → set **expiry** → choose **Nearby devices** (same UX metaphor as OS share).
2. **Recipient:** Accept → verify **who is sending** (name + avatar + optional short code) → import into **local vault** under clear labeling (“shared by X, expires Tuesday”).
3. **Household dashboard:** Sender sees **active grants** (what, to whom, until when); **revoke** in one action.

#### 3.6.5 Security and packaging (brainstorm-level)

- **Encryption in flight:** Session key established via **ephemeral key exchange** (e.g. ECDH) over the local channel; payload encrypted with **AEAD** (authenticated encryption).
- **Binding:** Optional **visual/short-code confirmation** to resist wrong-device delivery in dense environments.
- **Format:** Versioned **export package** (JSON + schema id + signatures) so recipient app validates before merge.
- **No silent merge:** Conflicts (recipient already has a field) resolved with **explicit UI** or per-field policy.

#### 3.6.6 Platform reality (implementation note, not a commitment)

- **Same-ecosystem** transfers are typically smoother (e.g. Apple ↔ Apple via system frameworks); **cross-OS** may require **standardized BLE + Wi-Fi Direct** or **QR bootstrap + socket over local LAN** when both devices share the same Wi-Fi (still **no internet relay** if payloads stay on LAN). Product should **phase** support: v1 same-OS proximity; v2 cross-OS where feasible.

### 3.7 Current truth + historical trail (renewed passports, licenses, and other changing facts)

Identity and household facts **change over time**: a new passport, a renewed driver license, a moved address, a new insurance card. The product should treat each **logical piece of information** (for example “passport number for Alex” or “driver license for Jordan”) as having:

- **One current value** — What summaries and assisted form filling use **by default**: always the **latest** value the user has confirmed after an upload, a manual edit, or an approved save from a form session.
- **A retained history** — Older values are **not silently discarded** when something newer arrives. Each stored past value keeps a **validity window** in time: **effective from** (when this value became the current one) and **effective until** (when it was superseded; the oldest entry may use an **effective from** inferred from first save or upload).

**Typical ways “current” moves forward:**

- User adds a **new photo or file** for the same kind of document and **confirms** it replaces the previous one for those fields.
- User **edits** a value and saves (with policy for whether the prior value closes at that moment).
- User chooses **save for next time** after filling a form and agrees to **overwrite** an existing field.

**Why keep a trail:**

- **Confidence:** Users can see **what was on file** during a past period without guessing.
- **Rare forms** that ask for prior numbers or dates.
- **Corrections** without destroying the ability to see **when** something wrong was current.

**Retention:** Users can **delete** individual past entries or **clear history** for a field while keeping only the current value; optional caps (e.g. keep last *N* versions or prune older than *T*) belong in product settings.

---

## 4. Brainstorming dimensions

### 4.1 Data model (sketch)

Think in terms of **entities** not “forms”:

- **Person** (self, spouse, child, other dependent).
- **Household** (grouping, shared addresses).
- **Document** (document type/category, OCR status, optional **retained file** reference—image or PDF—when the user opts in to **keep a scan** for uploads, with same encryption posture as other local secrets).
- **Field** (typed key-value with validation: phone, SSN pattern, date).
- **Field value history** (conceptual): for each logical field or document-linked group, a sequence of values, each with **effective from**, **effective until** (empty while current), link to **what replaced it**, and **source** (upload, OCR pass, manual edit, form save).
- **Form profile** (saved mapping from “our schema” to “this site’s quirks”).
- **Sharing grant** (grantor, grantee identity/role, scoped subjects + fields, issued at, valid until, revoked flag, optional device binding).
- **Household membership** (who belongs to the logical household; who may **initiate** shares vs **receive** only—useful for minors’ devices).

This supports both **navigation UI** (“show me everything about Alex”) and **autofill** (“use Alex’s school profile”), plus **governance UI** (“who currently has a live grant for Sam’s medical subset?”). **Everyday autofill** uses **current** values only unless the user explicitly selects a **past** value for an exception.

### 4.1.1 Provenance and history together

**Provenance** (where the latest value came from) and **history** (what was true in which period) work together: the **current** row carries the latest provenance; **earlier** rows keep their own source and time bounds for audit and review.

### 4.2 OCR strategy

- **On-device models** where possible (latency, privacy).
- **Human-in-the-loop**: OCR proposes; user confirms—avoids silent wrong autofill on legal/medical forms.
- **Selective retention of files**: default posture product-tuned (e.g. **fields only** unless user opts in). For opted-in categories, **retain encrypted scan/file** alongside structured fields; clear **UI to delete** the file only, or the whole document record.
- **Live scan vs upload**: same OCR pipeline after a **raster** is available; **live scan** may add **capture-time** UX (multi-page, retake, crop) and provenance label **“Scan on [date]”** vs **“Imported from file / photo.”**

### 4.3 Trust and transparency

- **Data inventory** screen: what exists, how big, last changed, export/delete.
- **Provenance for form-driven changes**: when values are **updated** from a form session, record source as **user confirmed on [date] from form** (or similar) so updates are distinguishable from OCR-only or manual profile edits.
- **History per field or document type**: show **current** value prominently; expand to see **earlier values** with **from / until** times and source (e.g. “Replaced when new passport photo added on [date]”).
- **Saved document copies** (when enabled): per person, show **which** retained scans exist (type, date), **preview** only after unlock, **delete**, **replace**—and whether each is used for **upload** vs **reference only**.
- **Network disclosure**: which calls are made (auth only) and **what they cannot contain**.
- **Sharing transparency**: sender **active grants**; recipient **imports with provenance** (“received from…, expires…”); optional **audit log** of share/revoke events on-device.

### 4.4 Accessibility and stress cases

- Older users and **motor limitations**: large tap targets, readable review screens.
- **Session loss**: recovery of in-progress form state locally without sending content to servers.

---

## 5. Non-goals (important for clarity)

- **Not** a generic password manager (though it may integrate alongside one).
- **Not** a cloud document vault unless explicitly added with different threat model.
- **Not** guaranteed automation on every site (anti-bot, iframes, CAPTCHAs set a ceiling).
- **Not** legal advice on submissions; the user remains responsible for accuracy.

---

## 6. Open questions (for later resolution)

1. **Encryption at rest**: OS keystore only vs SQLCipher vs file-based encryption—threat model dependent.
2. **Cross-device sync**: absent by default as **cloud sync**; **offline selective sharing** (section 3.6) is the preferred way to align multiple household devices with explicit scope and expiry. Optional **user-owned** encrypted file export to USB remains a fallback.
3. **Desktop vs mobile-first**: which platform carries the most pain for the founding audience?
4. **Enterprise vs consumer**: schools/HR might want MDM-friendly deployment; different sales motion.
5. **Regulatory labeling**: marketing “no data leaves device” must match engineering and incident response reality.
6. **History retention defaults**: how many versions or how long to keep closed intervals; handling when **effective from** is unknown for very old entries.
7. **In-app form assist**: which OS capabilities and partner integrations are acceptable for **third-party native apps** vs **best-effort** with copy fallback.
8. **Retained document files**: max size per device, compression rules, and whether **sharing grants** may include file blobs by default (recommend: **off** unless opted in).
9. **Profile disambiguation**: rules for when **auto-suggested** “form for child X” is allowed vs **must confirm** (e.g. twins, same first name).

---

## 7. Summary

The idea bundles **structured local memory** (RDBMS + OCR-assisted capture) with a **form copilot** that respects **review**, **OTP reality**, and **minimal backend trust**—with explicit **which household member** each form applies to (self, partner, children, others) before fills and saves—delivered **in Chrome** via **extension + companion app** (with **form-only** activation and **non-interference** with native autofill), and on **tablet/phone** additionally for **forms inside other apps** where feasible. Users may **opt in** to **retaining encrypted scans** of important documents (license, photo ID, vaccination records, etc.) for **upload** fields, alongside extracted fields—still **on device**, not on your servers. **Current value plus a time-bounded trail of superseded values** keeps **latest data** ready for everyday use while preserving **clarity and auditability** when documents renew or errors are fixed. Adding **offline, time-bound, field-scoped sharing** between trusted devices addresses **household coordination** without turning the product into a **cloud family vault**. The brainstorming above is meant to stay **product- and ethics-aware** before committing to a specific stack or feature cut list.
