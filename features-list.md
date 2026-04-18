# Features list: mandatory vs wish list

This document separates **mandatory** capabilities (required for the product to be coherent, trustworthy, and aligned with its privacy story) from a **wish list** that would make the platform **formidable** in market—without turning every wish into scope creep for v1.

**Related docs:** `idea-brainstorming.md`, `devils-advocate.md`, `market-analysis.md`, `how-secure-is-the-data-locally.md`, `user-interaction-screens.md`, `brainstorming-topic-filling-form-in-another-app.md`.

---

## 1. Mandatory features (must-have)

These are **non-negotiable** for a credible first product that matches the stated vision: **local structured memory**, **form assistance**, **household governance**, **minimal remote surface**, and **honest** positioning.

### 1.1 Local data plane

| Feature | Notes |
|--------|--------|
| **On-device relational store** | SQLite or equivalent; entities for people, relationships, addresses, and other structured fields—not a single flat blob. |
| **Manual entry & edit** | Users can add and correct data without OCR; OCR is an accelerator, not the only path. |
| **Basic provenance** | At minimum: source type (manual vs OCR vs **generative ingest**), and link to source document when applicable. |
| **Current value + history trail** | For each logical field (or document-linked group): **one current** value used for summaries and autofill; **prior values** retained with **effective from / effective until** (supersession times) and source (upload, edit, form save). New passport, renewed license, or correction **updates current** and **closes** the previous interval—no silent overwrite without history (unless user explicitly chooses “discard past” per field). |
| **Delete & export (local)** | User can delete records and export their structured data in a documented format (for backup or migration), **without** requiring cloud upload of payload. |

### 1.2 Capture & OCR

| Feature | Notes |
|--------|--------|
| **On-the-fly document scan** | Built-in **live camera** capture of physical documents (single or multi-page): user scans **now**, with optional alignment/corner hints, retake, and flashlight where available—then same **generative ingest + optional review/edit** path as uploads. |
| **Upload from gallery or files** | Pick **existing** photos or saved files (images, PDFs where supported)—for “already have a picture” or laptop-first use. |
| **Word and Excel import** | User uploads **`.docx` / `.doc`** (where supported) and **`.xlsx` / `.xls`** (where supported); **parse on-device** into tables/text; **generative model** infers mappings and **creates/extends** local tables as needed, **persists**, then **preview/edit** UI—**no** macro execution; optional **retain original file** in encrypted storage like other document types. |
| **Import folder (batch OCR)** | User **opts in** to selecting a **folder** (where the OS allows); app scans for supported file types (including **Office** where listed), runs **OCR on raster-like files** and **parse on Word/Excel** on-device, runs **generative structuring** and **automatically writes** to local memory (**AI-driven**, **no** human confirmation step before commit); **import activity** records per-file outcomes for **optional** audit, edit, or rollback; **person assignment** per item or explicit batch rules. **Desktop** typically full folder; **mobile** may use **folder picker** or **multi-file** flows per platform. |
| **Watched folder (incremental import)** | User **opts in** to **one or more** folders the app **monitors** for **new or updated** supported files. On each qualifying file, the app runs the **same** pipeline as batch import: **OCR/parse → generative structure → local DB**. **Desktop:** prefer **filesystem change notifications** while the app runs (and optionally a lightweight **background agent** or **scheduled** job per product policy). **Mobile:** where **continuous** watch is limited, use **rescan on foreground**, **periodic rescan while open**, or **explicit “check for new files”**—behavior **platform-defined**. Includes **pause** per watch, **debounce** for partial copies, **ignore patterns** (e.g. temp files), **dedupe** by file identity + hash, optional **notification** when new items are ingested, and **default person** for new rows. |
| **On-device OCR pipeline** | Text extraction runs locally; no upload of document content to your backend. |
| **On-device Office parsing** | Structured extraction from Word/Excel locally; same **no backend** rule for file content. |
| **Generative structure + dynamic local schema** | A **generative model** (default **on-device** for privacy) **infers** how extracted text maps to people and fields, **creates or alters** SQLite tables/columns when needed, and **stores** values—**without** requiring human confirmation as a prerequisite for persistence. **Post-ingest** confidence, display, and edit mitigate wrong extractions; **sensitive-field** policies may still add **extra prompts**. |
| **Supersede on new capture** | When the user adds a newer **scan or upload** of the **same** document type (e.g. new passport), guided flow: map to existing logical fields → **replace current** → prior values move to **history** with timestamps; **optional** replacement/supersession of **retained scan file** per user choice. |
| **Optional retained document files (on-device)** | User may **keep encrypted copies** of scans/files (e.g. driver license, passport/photo ID, vaccination record, insurance card) for **form upload** needs—not only extracted text. **Per capture or type:** store **file**, **fields only**, or **both**; **delete** anytime. |
| **Sensitive-field safeguards** | Configurable confirmation or masking for highest-risk field types (e.g. government IDs, full account numbers—exact taxonomy product-defined). |

### 1.3 Household memory UI

| Feature | Notes |
|--------|--------|
| **Navigate by person** | Clear lists and detail views: who is in the household, what is stored per person. |
| **Saved scans library (when enabled)** | Per person: see **document types** with a **kept file**, date, quick actions (preview behind lock, replace, remove file only). |
| **Create / update / delete** | Full CRUD for people and structured fields the product supports at launch. |
| **View history** | Per field or document group: **current** value first; **expand** to see earlier values and **when each was current** (from–until). Optional delete of individual historical rows. |
| **Household-level clarity** | Obvious model for “self,” dependents, and relationships sufficient for forms and sharing grants. |
| **Profile picker for forms** | UI to choose **which household member** a form applies to when starting or changing assist; aligns with relationship labels (parent vs child forms). |

### 1.4 Form assistant — three scenarios (desktop, tablet, mobile)

| Feature | Notes |
|--------|--------|
| **Chrome browser extension + companion app** | User installs an **extension for Chrome** (primary); extension communicates **only** with the **locally installed companion app** that holds structured memory—**no** household payload on your backend for fill. Installing the extension **installs or updates** the compatible app in the background (or clear one-time install flow). |
| **Form-page detection (browser)** | Extension **detects** whether the active tab is actually a **form** (inputs, semantics, heuristics). **Only on form pages**: offer assisted fill and guided next steps. **Non-form pages**: extension stays **inactive** (no injection, no intrusive UI). |
| **Respect browser native autofill** | If the user uses **Chrome autofill** or another password manager, the platform **does not override or interfere** with those behaviors. Assisted fill is **user-invoked** or **non-conflicting** per policy—never a silent war with native suggestions. |
| **Scenario A — Desktop / laptop** | User fills forms in **Chrome** as usual; extension + companion app supply values from local memory when the user asks and when the page is a form. |
| **Scenario B — Tablet** | Same **Chrome + extension + companion app** behavior as desktop **plus** ability to help with **forms inside other apps** (not only the browser)—product-defined mechanism (e.g. accessibility, overlay assist, or app-specific integrations) while keeping data **on device**. |
| **Scenario C — Mobile phone** | Same as tablet: **Chrome path** identical behavior; **in-app forms in third-party apps** supported as a **second** surface alongside the browser. |
| **Optional: in-app URL / embedded browser** | User may still open a link **inside** the companion app for users who prefer not to use Chrome; same mapping, review, and fast-path modes. |
| **Household profile (subject) for this form** | User **selects or confirms which person** the form is for—**self, spouse/partner, each child, or other member**. All fills, gaps, saves, and attachments are scoped to that profile for the session; **ask explicitly** when ambiguous; optional **per-site or per-link** remembered default (user-controlled). |
| **Session indicator** | Persistent **“Filling for: [Name]”** (or relationship label) with **Change profile** before applying sensitive data. |
| **Inject or apply stored values** | Map local fields to inputs (DOM in browser; native or platform-assisted in other apps) via heuristics + saved per-site overrides + user nudges—from the **active** profile’s data. |
| **Detect gaps vs local memory** | Before or while filling, identify **required or requested** fields that have **no** (or insufficient) value in local memory for the **chosen person**; **surface a clear prompt** to enter missing information—not silent skips. |
| **Prompt to store newly supplied gaps** | After the user fills in missing information, ask: **save to local memory for future use?** (Yes / No / Decide later)—aligned with section 1.6; respect sensitivity tiers. |
| **User-chosen mode: review vs fast path** | **Review then submit** and **minimal-review / go-ahead** path—user decides per session or per preset, across surfaces. |
| **Graceful degradation** | When automation fails: structured preview, copy-to-clipboard, field highlight—**never** a dead end. |
| **Scan or upload while filling** | From companion app or helper: **Scan document now** or **Choose file / photo** so the user can add missing details during a session; flows into review and optional save (sections 1.5–1.6). |
| **Attach from saved documents** | On forms with **file upload** controls: offer **pick from locally retained scans** (matching type where possible), with user confirmation—**no** round-trip through your servers. |
| **Session survivability** | Reasonable recovery of in-progress form state **locally** (crash/rotate), without sending form content to your servers. |

### 1.5 OTP and multi-step flows

| Feature | Notes |
|--------|--------|
| **Same-session completion** | User completes SMS/email OTP **in the browser tab or third-party app** (user-mediated); no server-side OTP proxy. |
| **UX for OTP friction** | Visible OTP field focus, resend awareness, timeout messaging—reduce abandonment without harvesting codes. |

### 1.6 Review-time edits, missing fields, & local persistence prompt

| Feature | Notes |
|--------|--------|
| **Inline edits during review** | User can correct values before submit—whether those values **came from local memory** or were typed fresh. |
| **Persist updates to existing local values** | When the user **changes** information that **already exists** in local memory and agrees to save: **UPDATE** the stored field(s) in the local database (not only append new records). Apply **history / effective-until** rules per §1.1 where the product keeps a trail. |
| **Optional save for future (edits / updates)** | Prompt: whether to **replace on-file values** with what the user entered on the form—e.g. **“Update saved information?”**; default policy product-tuned (e.g. opt-in or confirmation for sensitive fields). Distinct from first-time **add**. |
| **Missing values surfaced explicitly** | If local memory lacks data needed for the form (or for the user’s chosen fill scope), **guide the user** to enter it before submit; optional **checklist** of “still needed” items. |
| **Optional save for future (newly entered gaps / inserts)** | After the user supplies information that was **missing** from memory, prompt: **store this in local memory for next time?** — **Yes / No / Decide later**; results in **INSERT** (or first-time set) of those fields. Batch or per-field per product policy. |

### 1.7 Privacy boundary & backend contract

| Feature | Notes |
|--------|--------|
| **Account-only remote API** | Registration, login, logout, password reset, session/device management as designed—**no** family PII or OCR payload fields on these APIs. |
| **No silent exfiltration of local memory** | App does not upload structured memory, documents, or form-fill values to your backend. |
| **Anonymous / non-identifying operational data only** | If telemetry exists: coarse events (e.g. success/fail, latency buckets, app version)—**no** field values, OCR text, or URLs that identify third-party services in a sensitive way (policy to be tightened in spec). |
| **In-app disclosure** | Plain-language explanation of **what** can leave the device (auth, optional telemetry) vs **what cannot** (PII payload). |

### 1.8 Offline selective sharing (proximity, “AirDrop-class”)

| Feature | Notes |
|--------|--------|
| **Create a share grant** | Sender selects **which people** and **which field groups / fields**, and **expiry** (time window or absolute end). **Retained scan files** only if **explicitly** included in scope (default: structured fields / metadata—not silent image packs). |
| **Proximity transfer without internet payload** | Deliver encrypted package **device-to-device** via OS-supported local channels (not via your API as data carrier). |
| **Recipient accept + import** | Import into local vault with clear labeling (from whom, expires when). |
| **Sender: active grants & revoke** | Dashboard of what is shared, to whom, until when; **revoke** remaining validity from sender device. |
| **Confirmation anti-misdelivery** | Short code or equivalent pairing step in crowded environments. |

### 1.9 Security baseline

| Feature | Notes |
|--------|--------|
| **OS lock integration** | Respect device PIN/biometric; optional **app-specific lock** for high-sensitivity apps. |
| **Encryption at rest** | At minimum OS-backed file protection; stronger options (e.g. SQLCipher) as roadmap allows—**mandatory** is “not plaintext casual access.” |

---

## 2. Wish list (formidable in market)

These items **raise the ceiling**: differentiation moats, enterprise readiness, reliability at scale, and delight. They are **not** all required to ship a first honest version; sequencing matters (see §3).

### 2.1 Form engine & reliability

| Feature | Why it matters |
|--------|----------------|
| **Extensions beyond Chrome** | Safari, Firefox, Edge—same **local companion** pattern where store policy and engineering allow. |
| **Site packs / curated mappings** | Officially maintained mappings and tests for high-traffic government, benefits, insurance, and education portals—cuts variance and support load. |
| **Shadow DOM / iframe strategies** | Deeper automation where sites hide fields—fragile but high value when it works. |
| **Per-site learning (local only)** | Remember user-accepted or user-corrected field bindings **on-device**—improves repeat visits without cloud ML on content. |
| **Accessibility-aligned automation** | Prefer stable hooks (labels, roles) where available—more robust and more ethical. |

### 2.2 OCR & intelligence (still local)

| Feature | Why it matters |
|--------|----------------|
| **On-device generative models for structure** | Larger or specialized models (where hardware allows) improve **mapping** and **schema decisions** without sending document content off-device—supports the **dynamic table** story. |
| **Document-type templates** | “Passport,” “lease,” “W-2,” “immunization”—faster field extraction with fewer errors. |
| **Desk / laptop camera & scanner workflows** | Where the platform allows: continuous capture from a webcam or driver for a connected scanner—same review pipeline as mobile scan/upload. |
| **Batch folder import polish** | **Duplicate detection**, **pause/resume**, **parallel OCR** where safe, **per-folder import presets** (e.g. “these are all Sam’s school PDFs”). |
| **Watched-folder polish** | **Deep vs shallow** watch (include subfolders or not), **max files per day** or **throttle** to protect battery, internal **processing queue** (priority/order only—not a user confirmation queue), **audit log** of “file X → ingested at T” for watch-driven events. |
| **Spreadsheet import templates** | Saved **column mappings** for recurring school/HR spreadsheets—**local** presets only. |
| **Compressed / “web-ready” exports** | Optional local generation of smaller PDF/JPEG for sites with size limits—still on-device. |
| **Confidence scores & snippet preview** | User trusts **review/edit** UI when they see **why** the model placed a value. |
| **Optional second-pass models** | Premium or on-demand heavier models for poor scans—**still on-device** if privacy story holds. |

### 2.2.1 History & retention (wish list)

| Feature | Why it matters |
|--------|----------------|
| **Retention policies** | User-defined caps: keep last *N* versions, or drop segments older than *T*—balances storage with audit needs. |
| **“What was current on [date]?”** | Read-only query for disputes or taxes—uses closed **from/until** intervals. |
| **Export history summary** | Printable or shareable (user-initiated) timeline for one person or one document type—lawyer/accountant handoff without cloud. |

### 2.3 Household & collaboration

| Feature | Why it matters |
|--------|----------------|
| **Household roles & permissions** | Who may **initiate** shares, **receive only**, or **manage** children’s records—mirrors real custody and caregiving. |
| **Cross-platform proximity sharing** | Android ↔ iOS (and desktop) with clear **compatibility matrix**—huge for real families. |
| **LAN-assisted pairing (no cloud relay)** | QR bootstrap + encrypted transfer on local Wi-Fi when proximity stacks differ—fallback for mixed environments. |
| **Read-only “kiosk” mode on a tablet** | Caregiver device for forms with **no edit** rights to canonical vault—delegation without governance chaos. |

### 2.4 Trust, audit, and compliance posture

| Feature | Why it matters |
|--------|----------------|
| **Full on-device audit log** | Share/revoke/edit events for accountability—supports disputes and enterprise buyers. |
| **Data inventory & “risk” dashboard** | What categories exist, age of data, last shared—user empowerment. |
| **Export for supervised review** | Encrypted diagnostic bundle **user-initiated** for support—without routine cloud logging. |
| **Regional compliance packs** | Documentation and defaults tuned to GDPR, COPPA-adjacent flows for minors, etc.—**product + legal** work, not just code. |

### 2.5 Security hardening

| Feature | Why it matters |
|--------|----------------|
| **SQLCipher or equivalent** | Stronger at-rest protection especially if device passcode is weak. |
| **Wipe on failed unlock / duress** | Niche but valued by high-threat users—careful UX. |
| **Recipient-side enforced expiry UX** | Best-effort auto-expire shared imports; clear UI when expired—**honest** about limits (cannot force another OS to erase). |

### 2.6 Product surface & growth (without selling user data)

| Feature | Why it matters |
|--------|----------------|
| **Premium OCR / site packs** | Sustainable revenue aligned with **software value**, not PII. |
| **Family / household subscription** | Pricing tied to **devices or seats**, not hosted content. |
| **Enterprise / MDM deployment** | Schools, HR, agencies that mandate device-bound data—**distribution** channel. |

### 2.7 Integrations (optional, privacy-preserving)

| Feature | Why it matters |
|--------|----------------|
| **Password manager handoff** | Open-fill or copy workflows—users keep secrets in the vault, structured identity here. |
| **Calendar reminders** | “Renewal / deadline” for documents—**local** reminders, not server scheduling of PII. |

---

## 3. Phasing guidance (brief)

| Phase | Focus |
|-------|--------|
| **MVP** | §1 mandatory: local store + **generative ingest** (default on-device) + dynamic schema + household UI + **profile/subject selection for each form** (self, partner, kids, other members; ask when unsure) + **optional retained document files** (opt-in, key types) + **Word/Excel import** (at least **xlsx/docx** parse + generative map + **edit**; **no** macro execution) + **folder batch import** (where OS supports folder/multi pick; **automated persist** + **import activity**) + **Chrome extension + companion app** (form detection, user-invoked fill, native-autofill coexistence, **attach from saved** where possible) + optional **in-app** assist on mobile/tablet where feasible + account boundary + baseline security + **core** proximity sharing (same-ecosystem first if needed). **Watched-folder** incremental import is **not** required for MVP cut (see **Hardening**). |
| **Hardening** | Site packs, **watched-folder** incremental import (real-time or scheduled per platform), audit log, encryption upgrades, clearer telemetry policy, broader in-app coverage. |
| **Scale & moat** | Cross-platform sharing, enterprise, premium local models, deep site coverage, **additional browsers**. |

---

## 4. Explicit non-features (guardrails)

To stay formidable **and** credible, the following should **not** be smuggled in as “wish list” without a **new** threat model and user consent:

- **Cloud sync of structured family PII** as default.
- **Server-side** processing of documents or form fields for “convenience.”
- **Default retention of every scan image** without **explicit** user consent per category—**opt-in** for kept files protects trust and storage.
- **Extension or app uploading** household fields to your backend **to perform** browser fill (fills must remain **local companion–driven**).
- **Automated OTP retrieval** via your backend (breaks privacy story and abuse profile).

---

## 5. Summary

- **Mandatory** = local structured memory with **generative structuring** (default on-device), **dynamic schema** in SQLite, **Word/Excel import** with on-device parsing and **generative map + edit**, **user-chosen folder batch import** with on-device OCR and **fully automated persist** plus **import activity** for optional fixes, **watched-folder incremental import** (same pipeline when **new files** appear—**platform-dependent** watch vs rescan; see §1.2 row and §3 **Hardening** phasing), **household profile selection** (whose form this is: self, partner, children, other members) with session indicator and **change** affordance, **optional retained document files** (user-controlled, on-device, for uploads), **Chrome extension + companion app** form assistance (form-only activation, coexistence with browser autofill, **attach from saved documents** where applicable), **gap detection** with prompts to enter missing information and **optional save** of **new** values (**insert**), plus **optional update** of **existing** local values when the user changes information on the form and confirms (**insert + update**, never silent), tablet/phone **in-app** paths where feasible, review/fast paths and OTP-friendly UX, strict backend minimization, household CRUD UI, proximity-based selective sharing with expiry and revoke, and a security baseline.
- **Wish list** = curated site coverage, deeper automation, cross-platform sharing, enterprise and compliance depth, premium local intelligence, and revenue tied to **capability**—not to **hosted identity data**.
