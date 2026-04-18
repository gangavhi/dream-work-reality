# Idea brainstorming: Dream Work Reality

This document captures an open-ended exploration of the product concept: a **local-first** application that uses **OCR and parsers** plus **on-device generative models** to **infer structure**, **fit** extracted information about people and families into a **relational database** (creating tables or columns when needed), and helps users **complete online forms** using that data—with **post-ingest review and edit**, support for **OTP-heavy** flows, and explicit control over **what (if anything)** crosses a **network boundary**. It also covers **offline, selective sharing** of structured memory with trusted devices (household members) for **bounded time**, without routing that payload over the **internet**.

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

- **OCR and parsers** produce **raw text and layout** from captures and files; a **generative model** (intended to run **on-device** by default so document content stays local for structuring) **decides** how that content **fits** the household: which **entities** and **fields** apply, and—when needed—**creates or extends** tables and columns in the **local relational store**, then **writes** the structured values. Structure is **not** held back until a human or rules engine “blesses” it: the model **commits** to the DB, with **provenance** and **post-hoc edit** so users can correct mistakes. **Optional** cloud-based generative inference, if ever offered, must be a **separate, explicit opt-in** with its own privacy disclosure—not the default story.
- **Several complementary ways to bring documents in** (capture and parsing **on-device**; **default** generative structuring **on-device**; none sends raw document content to your backend):
  - **On-the-fly scan** — The user points the camera at a physical document **in the moment** (wallet card, letter, form on a desk). The app captures one or more pages, optionally with guidance (alignment, corners, lighting) so the image is readable before OCR runs. Suited to “I have it in front of me right now” and to **quick capture during a form** without switching to another app.
  - **Upload** — The user picks an **existing** photo from the gallery, or a **file** from storage (PDF, image—where the platform allows), often for “I already have a picture” or laptop workflows.
  - **Word and Excel import** — The user can **upload** Microsoft **Word** (e.g. `.docx`) and **Excel** (e.g. `.xlsx`, and legacy `.xls` if supported) files—or include them in **folder import** when those extensions are allowed. The app **parses** structure **on-device** (paragraphs, tables, sheets, cells—no cloud conversion of file content for storage). The **generative layer** infers **column→field** or **row→person** mappings (and can **mint** new columns/tables when household-specific labels don’t match a fixed schema) and **automatically persists** results locally—**no** step where candidates sit uncommitted until a person confirms. The UI may show **what was stored** afterward so the user can **fix** mis-mapped cells or merged-sheet edge cases. **Macros** (VBA) are **not executed**; data import only.
  - **Folder import (batch)** — If the user **chooses to**, they can point the app at a **folder** (directory) they are allowed to read—typically strongest on **desktop**; on **mobile**, OS file pickers may offer **folder selection** or **multi-select** rather than arbitrary filesystem trees. The app **enumerates** supported files (images, PDFs, **Office formats where supported**—product-defined extensions and size limits), runs **OCR on raster-like files** and **structured parse on Word/Excel** locally, and **automatically processes each file** through the same **AI-driven generative structuring pipeline**: values are **written to the local DB as inferred**—there is **no** “review queue” where candidates are **not** committed until the user confirms per file or in batches. **Import activity** (or an **ingest log**) records outcomes so the user can **audit**, **edit**, or **roll back** after the fact. Provenance records **source path or folder label** (not necessarily full path if privacy-redacted) and **import batch id** for traceability.
  - **Watched folder (incremental / continuous)** — The user can **opt in** to **keep watching** one or more chosen folders for **new or updated** files that match supported types. When a qualifying file appears (or finishes copying—see debounce below), the app runs the **same** pipeline: **OCR/parse → generative structure → persist** to local memory, with provenance such as **“watched folder [label] on [date].”** **Implementation notes:** On **desktop** OSes, **file-system change notifications** (e.g. inotify/FSEvents/ReadDirectoryChangesW) are the preferred trigger; on **mobile** platforms where **background** access and **always-on** directory watches are constrained, the product may use **periodic rescan while the app is open**, **rescan on foreground**, or **push notification from a companion desktop**—exact behavior is **product- and platform-defined**. **Controls** should include: **on/off per folder**, **pause** (temporary stop without removing the watch), **default person** for ingests, **ignore patterns** (e.g. `*.tmp`, `~$*`), **debounce** after create events so **partial downloads** are not OCR’d twice, **dedupe** by stable file identity + content hash so moves/retries do not duplicate rows, and optional **notify** when N new items are ingested. This does **not** broaden scope beyond **user-authorized paths** (still aligned with §5 non-goals).
- **RDBMS on device** enables relationships: person ↔ address ↔ employer ↔ dependent ↔ document metadata; **schema can evolve** as the generative layer adds **tables or columns** for new document types or labels.
- **Provenance**: optional trail (“this field was **inferred and stored** from OCR of document X on date Y,” **“generative mapping from Word/Excel file X on date Y,”** or manual edit) to support corrections and trust, including whether the source was **live scan** vs **upload** vs **Office import**.
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

**Field mapping** connects local schema fields to page inputs (heuristics + saved per-site overrides + user nudges + **generative household resolution** when canonical data is **sparse**) in **whichever** surface is active (extension DOM, in-app WebView, or in-app native form mapping). For **multi-person** forms, mapping is **role-aware**: inputs are matched not only to **field names** but to **semantic roles** (**patient/child**, **parent/guardian**, **subscriber**, **emergency contact**) and resolved to the correct **Person** via **household relationships**—so a pediatric form can pull **child demographics** and **parent contact** in one pass without treating them as one blob. When the **preferred** person’s field is **empty**, the **generative layer** may **select** an alternate **household source** with **documented reasoning** (confidence, provenance)—not only **leave blank** or **interrupt** the user.

**Which household member is this form for—and who else does the form need?** Real forms often have **two layers**: (1) a **primary subject**—who the application is *about* (e.g. the **child** at a doctor visit, the **student** on a school form)—and (2) **other members’ facts** on the same page (e.g. **parent/guardian** name, phone, insurance subscriber, emergency contact). The product should treat this as **one seamless session**, not “only one profile’s data may be used.”

- **Household roles and relationships:** Each **Person** record supports **display roles** the user chooses (e.g. **Father**, **Mother**, **Parent**, **Guardian**, **Child 1**, **Child 2**, **Self**) plus **structured links** between people (**parent of**, **guardian of**, **partner of**, **household member**) so the system knows **who is whose parent** without guessing from first names alone. Roles are **user-editable** (blended families, grandparents, other caregivers) and drive **which profile supplies which field class** when a form mixes patient and parent blocks.
- **Form subject (primary) vs contributing profiles:** The user picks **who this form is primarily for**—e.g. **“This form is about: Sam”** for a pediatric intake. The assistant **also** resolves **guardian/parent/emergency** fields from the **appropriate** other members using roles (e.g. **Mother** → Jordan’s phone; **Father** → Casey’s email), heuristics on label text (**Patient** vs **Parent**), and saved **per-site** overrides. A compact session banner can read like **“Form about: Sam · Using: Jordan (parent), Casey (parent)”** so scope stays transparent.
- **Incomplete canonical data (real households):** **Not every adult** has a full row for every field—one parent may have **work phone and insurance card** on file; the other may only have **email**; data may have arrived from **one** parent’s scans. The product should **not** treat missing slots as “user must type everything” when the **generative layer** can make a **defensible, role-aware choice** from what **does** exist in the household graph.
- **Generative household field resolution (fill-time):** An **on-device generative model** (aligned with the **structuring** models; same privacy defaults) **reasons** over **all** household members linked to the form subject—**field semantics** (guardian vs subscriber vs emergency), **role labels**, **who has which attributes populated**, **recency**, **consistency**, and **confidence**—to **select** which stored value to place in a given input when the **naïvely “correct”** profile is **empty** for that attribute. Example: form asks for **Mother’s cell**; **Mother** has no mobile on file but **Father** has the only household **mobile**—the model may supply it for a **generic “parent/guardian phone”** line with clear **provenance** (**“Only number on file—Casey”**), or prefer **not** to map a **mislabeled** “Mother” field if confidence is low. The goal is **thoughtful automation**, not **random** pick: **prefer** the user’s time over unnecessary prompts when inference is **high-confidence**; **ask** when two adults have **conflicting** equally valid numbers and the form demands **one** specific role.
- **Prefer asking** when the **form subject** or **high-stakes role** is ambiguous: **“Who is this form for?”** with **Me**, **My partner**, and **each child** (by name), plus **Other household member**. Reserve **explicit** disambiguation for cases the model **cannot** resolve safely—e.g. **two** filled parent phones and the form requires **Mother** vs **Father** specifically with **no** semantic slack—rather than asking the user to **manually bridge** every gap the model could have filled from **existing** canonical data.
- **Use light hints** only when confidence is high (page title, field group labels). Hints never **auto-switch** the **form subject** without confirmation if multiple children (or adults) could match.
- **Obvious, persistent indicator** during the session: at minimum **who the form is about**; optionally **which other members** are contributing to this fill—**Change** on each so mistakes are fixable before sensitive apply.
- **Gap detection** and **save / update prompts** must be **field-aware**: “Missing **Sam’s** date of birth” vs “Missing **Jordan’s** phone for guardian block”—and write-back targets the **correct** person’s row, not only the form subject.
- **Retained document attachments** (e.g. upload child’s insurance card) stay tied to the **right** person’s document store; parent ID uploads map to the parent profile when the field group says so.

**Single-profile-only flows** (simple “my address” forms) remain a **degenerate case**: form subject = only contributor.

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

- **One current value** — What summaries and assisted form filling use **by default**: always the **latest** value **stored** after **generative ingestion**, a **manual edit**, an **approved save** from a form session, or a **user-confirmed replacement** when superseding a document.
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

- **Person** (self, spouse, child, other dependent)—each with optional **role labels** for UX and mapping (e.g. Father, Mother, Child 1).
- **Relationship** (directed edges: parent/guardian of, partner of, **custom**—so “who fills in for whom” is queryable).
- **Household** (grouping, shared addresses).
- **Document** (document type/category, OCR status, optional **retained file** reference—image or PDF—when the user opts in to **keep a scan** for uploads, with same encryption posture as other local secrets).
- **Field** (typed key-value with validation: phone, SSN pattern, date)—including **dynamically added** columns when the generative layer introduces new labels.
- **Field value history** (conceptual): for each logical field or document-linked group, a sequence of values, each with **effective from**, **effective until** (empty while current), link to **what replaced it**, and **source** (upload, OCR pass, manual edit, form save).
- **Form profile** (saved mapping from “our schema” to “this site’s quirks”).
- **Sharing grant** (grantor, grantee identity/role, scoped subjects + fields, issued at, valid until, revoked flag, optional device binding).
- **Household membership** (who belongs to the logical household; who may **initiate** shares vs **receive** only—useful for minors’ devices).

This supports both **navigation UI** (“show me everything about Alex”) and **autofill** (“use Alex’s school profile”), plus **governance UI** (“who currently has a live grant for Sam’s medical subset?”). **Everyday autofill** uses **current** values only unless the user explicitly selects a **past** value for an exception.

### 4.1.1 Provenance and history together

**Provenance** (where the latest value came from) and **history** (what was true in which period) work together: the **current** row carries the latest provenance; **earlier** rows keep their own source and time bounds for audit and review.

### 4.2 OCR + generative structuring strategy

- **On-device OCR and parsers** for raw text/layout; **on-device generative model** (default) to **infer** field semantics, **fit** values into the relational model, and **apply DDL** (create/alter tables) when the schema needs to grow—**latency and privacy** favor local inference.
- **User correction loop**: ingestion **writes** first; the UI exposes **confidence**, **source snippets**, and **edit** paths so wrong extractions or wrong **person assignment** can be fixed—especially on legal/medical fields—without pretending humans must approve structure before anything is stored.
- **Selective retention of files**: default posture product-tuned (e.g. **fields only** unless user opts in). For opted-in categories, **retain encrypted scan/file** alongside structured fields; clear **UI to delete** the file only, or the whole document record.
- **Live scan vs upload**: same OCR pipeline after a **raster** is available; **live scan** may add **capture-time** UX (multi-page, retake, crop) and provenance label **“Scan on [date]”** vs **“Imported from file / photo.”**
- **Batch folder import**: **enumerate → OCR/parse → generative structure → persist** (**fully automated**; no human confirmation gate); optional **skip duplicates** (file hash), **pause/resume**, **max files per run** to protect battery and storage; **assign person** per item or default + bulk-edit—wrong assignment is a top risk, so UX must make **who this belongs to** explicit via defaults or **post-ingest** reassignment; **import activity** surfaces results for optional correction.
- **Watched folder**: **subscribe to changes** (where the OS allows) or **rescan on a schedule / on app resume** (where it does not) → same pipeline as batch; **debounce** new files; **ignore temp/partial** names; **track processed file ids** to avoid re-import loops when metadata changes.
- **Word / Excel**: **parse → generative map to entities/fields (with dynamic schema) → persist → preview/edit**; treat **merged cells**, **multiple sheets**, and **embedded images** as edge cases with **manual** fallback; **values** preferred over formulas where both appear (product-defined display of formula result if parsed).

### 4.3 Trust and transparency

- **Data inventory** screen: what exists, how big, last changed, export/delete; **batch imports** listed as **sessions** (date, folder label, count, **automation outcome** / per-file status in **import activity**) so users can audit what came from a **folder sweep**; **watched folders** listed with **last activity**, **paused** state, and **files processed** count.
- **Provenance for form-driven changes**: when values are **updated** from a form session, record source as **user saved on [date] from form** (or similar) so updates are distinguishable from **generative ingest**, OCR-only, or manual profile edits.
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
- **Not** unrestricted indexing of the user’s whole computer or phone—**folder import** is **explicit user choice** of a **bounded** path or file set.
- **Not** a **human-gated review queue** where structured candidates stay **uncommitted** until confirmation—**ingest is AI-driven and automated**; optional UI is for **audit and correction after** data is stored.
- **Not** a macro-enabled Office runtime—**no execution** of VBA or embedded scripts from user documents; **import data only**.
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
9. **Profile disambiguation**: rules for when **auto-suggested** “form for child X” is allowed vs **must confirm** before fill (e.g. twins, same first name)—distinct from **document ingest**, where the generative layer may still **infer** person but the user can **reassign** after the fact.
10. **Folder import limits**: max files per batch, max total size, supported extensions, and **iOS/Android** folder-picker behavior vs **desktop** full-directory access; **watched folder** semantics: debounce interval, background budget on mobile, and whether **duplicate** detection keys on path, inode, or hash.
11. **Office formats**: minimum supported **`.docx` / `.xlsx`**; whether **`.xls` / `.doc`** legacy and **macro-enabled** `.docm` / `.xlsm` are **excluded** by default.
12. **Household relationships**: how many **role** types ship in v1; handling **split custody**, **non-parent guardians**, and **multiple adults** when a form asks for “Parent 1 / Parent 2.”
13. **Generative fill from incomplete parent rows**: thresholds for **auto-select** vs **prompt**; how **provenance** is shown when a value came from a **different** household member than the field label suggests; **sensitive** fields (e.g. SSN) **excluded** from cross-person inference by default.

---

## 7. Summary

The idea bundles **structured local memory** (RDBMS + **OCR/parsers** + **on-device generative structuring** that can **create or extend schema** and **persist** inferred fields)—including **Word and Excel** import with **on-device parsing** and **automated** generative save plus **post-ingest edit**, plus **batch import** and optional **watched folders** that **auto-run** the same **fully automated** ingest pipeline when **new files** land in user-authorized directories (platform-dependent **watch** vs **rescan**), with on-device OCR and **import activity** for **audit and optional correction**—with a **form copilot** that respects **user-chosen review modes for forms**, **OTP reality**, and **minimal backend trust**—with **household roles** (e.g. father, mother, children) and **relationships** so a **form about one member** (e.g. child’s doctor visit) can still pull **parent/guardian** fields **seamlessly**—including **on-device generative resolution** when **canonical** parent rows are **incomplete** (the model **selects** the best available household source with **confidence** and **provenance**, rather than **defaulting** to empty fields or **unnecessary** user prompts)—with explicit **form subject** and **transparent multi-profile** scope before fills and saves—delivered **in Chrome** via **extension + companion app** (with **form-only** activation and **non-interference** with native autofill), and on **tablet/phone** additionally for **forms inside other apps** where feasible. Users may **opt in** to **retaining encrypted scans** of important documents (license, photo ID, vaccination records, etc.) for **upload** fields, alongside extracted fields—still **on device**, not on your servers. **Current value plus a time-bounded trail of superseded values** keeps **latest data** ready for everyday use while preserving **clarity and auditability** when documents renew or errors are fixed. Adding **offline, time-bound, field-scoped sharing** between trusted devices addresses **household coordination** without turning the product into a **cloud family vault**. The brainstorming above is meant to stay **product- and ethics-aware** before committing to a specific stack or feature cut list.
