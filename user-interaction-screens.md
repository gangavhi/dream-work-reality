# User interaction & screens (mobile, tablet, laptop)

This document describes what people **see and do** when using the platform—across phone, tablet, and laptop. It is written for **experience clarity**, not technical design.

---

## 1. How the experience adapts by device

| Device | What people notice |
|--------|-------------------|
| **Phone** | One main action at a time; bottom navigation for Home, People, Forms, and More; sheets slide up for choices; sharing uses the same “send nearby” habit people already know from their system. **Forms:** help in **Chrome** (via the add-on) **and** in **other apps** that show a form (when the product supports it). |
| **Tablet** | Same flows, with **more room**: lists beside details (e.g. family members on the left, one person’s information on the right); forms can show a wider review panel. **Forms:** same **Chrome** experience as on a computer **plus** support for **forms inside other apps** where available. |
| **Laptop** | Comfortable **keyboard and pointer**: faster typing during review; side-by-side layout more often; window can be resized and may remember its size next time. **Forms:** help appears **inside Chrome** while browsing—no need to copy everything from a separate window unless the user prefers opening a link in the companion app instead. |

**Common thread:** Information lives in the **companion app** on that device; a **small Chrome add-on** connects the browser to that app. **Layout and comfort** change by screen size; **Chrome behavior** is designed to feel the same on a small phone screen and a large monitor.

---

## 2. Account & signing in (only what touches the account)

These screens exist so people can have an identity with the service. **They do not ask for family details or document content.**

- **Welcome** — Short explanation of what the app does (keep your information on your device; help with forms **in Chrome and, where supported, in other apps**; share safely at home when you choose).  
- **Create account** — Email or phone, password, agree to terms.  
- **Sign in** — Identifier and password; link for “Forgot password.”  
- **Forgot password** — Steps to reset access; confirmation when done.  
- **Sign out** — Available from profile or settings; confirms so nobody signs out by accident on a shared computer.

*Nothing on these screens asks for children’s names, addresses, or scans.*

---

## 3. Home (first time and every day)

### 3.1 First visit after sign-in

- A **simple welcome** that explains three ideas in plain language:  
  - Add the people you care for.  
  - Bring in details by **scanning a document now**, **choosing a photo or file**, **importing a Word or Excel file**, **adding a whole folder of documents** (when you want), or typing yourself.  
  - When you’re ready, open a web form and let the app help you fill it—**you stay in control**.  
- One clear button: **Add someone** or **Set up my household**.

### 3.2 Home when data already exists

- A **calm summary**: number of people, optional reminder if something needs attention (e.g. “Review suggested details from last week’s photo”).  
- Shortcuts: **Open a form**, **View family**, **Share with someone nearby**.  
- Nothing noisy—this is a **home base**, not a dashboard of alerts.

---

## 4. People & household

### 4.1 Family list

- **Everyone in one scrollable list** — photo or initials, name, relationship (self, partner, child, parent, other).  
- **Search** at the top when the list grows.  
- Button: **Add a person**.

### 4.2 Adding or editing a person

- **Basics** — Name, how they relate to the household, optional photo.  
- **Contact & identity** — Phone, email, address fields grouped in sections people recognize from real life.  
- **Other sections** — School, work, health, insurance—**only sections you’ve turned on or that apply** (no endless empty forms on day one).  
- **Save** always visible; **Cancel** returns without saving when nothing critical was entered.

### 4.3 One person’s detail view

- **Sections** fold open (tap or click) so the screen never feels like one endless wall of fields.  
- Each field shows **where it came from** in human terms: “You entered this,” “From a scan you took on [date],” “From a file or photo you picked,” “**Placed by the assistant** from a photo on [date]—tap to fix if wrong,” “Updated while filling a form on [date].”  
- **What you see first is always the latest** stored information—the number, date, or address you would use on a new form today (after **generative ingest**, your edits, or a saved form session).  
- Actions: **Edit**, **Remove this person** (with a careful confirmation), **Share [name]’s details** (opens the sharing flow).

### 4.4 When something important gets renewed (passport, license, card)

- User adds a **new photo or file** for the same kind of document (for example a renewed driver license).  
- The app asks whether this **replaces** the previous details for those lines, or is **additional** (rare cases—two active documents). For a straight renewal, **Replace** is the default.  
- After the user confirms, the **new details become the main ones** everywhere—in lists, in form help, and in summaries.  
- The app explains in one line: **“We’ll keep your earlier details in history so you can see what was on file before, unless you delete that history.”**  
- If the user **only changes one line** by hand (typing), the same idea applies: the **updated line** is now the main one; the **previous value** moves to history with a clear **from / until** story.

### 4.5 History: what was true before (and when)

- On any field that has changed at least once, an action: **Previous versions** or **History**.  
- A simple **timeline**: each row shows the **value**, **from** [date/time or “since you saved on …”], **until** [date/time or “replaced on …”], and a short **reason** in everyday words: “Replaced by new passport photo,” “You edited this,” “Saved from a form on …”  
- **Current** is marked clearly at the top (“In use now”).  
- Optional: **Delete one past version** (with a warning) or **Clear all history for this field** while keeping only what’s current—only for people who want a smaller footprint.  
- **Forms** still offer **today’s value** by default; if a rare application needs an old number, the user can pick it from history **on purpose**—never by accident.

---

## 5. Bringing information in: scan now or upload something you already have

People should be able to add a document **in the moment** (paper in hand), use something they already saved—including **Word or Excel**—or pull in a **whole folder**; every path runs through **on-device capture/parse**, then a **generative assistant** that **decides structure**, **creates or extends** local database tables if needed, and **saves automatically**—**import activity** and **edit** flows catch mistakes **after** data is stored, not a queue that blocks saving until someone confirms.

### 5.1 Choose how to add

- **Scan document** — Opens the **camera inside the app** for an **on-the-fly** capture: the user holds the physical document up, fits it in the frame, and takes the picture (or several pages, one after another, if needed). Helpful hints may appear: **hold steady**, **move closer**, **better light**, **try again** if the shot is blurry.  
- **Choose from gallery** — Picks an **existing** photo already on the device (a screenshot, a photo taken earlier, an image from messages).  
- **Choose a file** — Especially on tablets and laptops: pick a **saved file** from disk (a scan, a PDF export, an image).  
- **Word or Excel** — Pick a **`.docx`** or **`.xlsx`** (and other supported types) the user already has. The app **reads the structure on the device**; the **generative assistant** infers **columns, rows, and fields** and **writes** into local memory (creating tables or columns when needed) **automatically**; the user can **open** that import afterward to **fix** a wrong mapping.  
- **Add everything from a folder** (when the user wants it) — The user can pick a **folder** of documents (or, on some phones, a **bunch of files at once**—whatever the system allows). The app **processes each supported file** in an **automated** pipeline: **OCR → structure → save**—**no** per-file confirmation gate. **Progress** shows how far the run has gotten; **import activity** lists what finished so the user can **open any item to correct** if something looks wrong. On **computers**, choosing a whole folder is usually easiest; on **phones**, the flow may look like **select multiple files** or **pick a folder in Files** depending on the device.  
- **Keep watching a folder** (when the user wants it) — The user can turn on **automatic import** for a folder they already chose: **new or updated** files that match supported types are picked up **without** running the full “import everything now” flow again. **Desktop** users may see **“Watching…”** with **last file processed** and **pause**; **phone/tablet** users may see **“We’ll check when you open the app”** or a **periodic scan** if the platform doesn’t allow true background folder watching—**honest** labeling per platform.

### 5.2 After a capture (whether you scanned or uploaded)

- The app shows **what it extracted** and **how it filed it**—names, addresses, dates, IDs—**already saved** in the local database unless the user **undoes** or **discards** this capture.  
- Clear actions: **Looks good**, **Edit fields**, **Wrong person—reassign**, **Discard this capture**.  
- Optional: **Which person does this belong to?** if it wasn’t obvious—especially important when **many files** came from one folder so the wrong person isn’t picked by habit.  
- The user can see **how this was added** in plain words later—for example **“Captured with camera on [date]”**, **“From a file you chose,”** **“From a Word or Excel file you imported,”** **“From folder import on [date],”** or **“From watched folder [name] on [date].”**

### 5.2.1 After you import Word or Excel

- The app shows a **preview** of what it understood—tables, rows, or sections—**after** it has **already written** structured rows into local memory.  
- The user can **adjust** column-to-field links, **reassign** rows to people, or **delete** a bad import if the file was the wrong one.

### 5.2.2 After a folder import (many files at once)

- Import is **fully automated**: nothing waits in a **review queue** uncommitted until the user approves.  
- **Import activity** shows each file with status: **Done**, **Needs attention** (e.g. low confidence or parse error), **Skipped** (unsupported or ignored).  
- Tapping or opening one file shows the **same** fix-up flow as a single document (section 5.2).  
- The user can **leave** while processing continues or **come back later**; data from completed files is **already in the profile**, with a clear path to **edit or roll back** per file.

### 5.2.3 Watched folders (new files arrive later)

- **What it is:** A **saved folder** the app **monitors** (where the OS allows) so that when the user **drops in** a new PDF, scan, or spreadsheet, the app runs **OCR / parse → generative save** in the **same** way as a one-shot batch import.  
- **Settings** (per watched folder): **On / Off**, **Pause** (temporary), **Include subfolders** (yes/no), **Default person** for this folder’s ingests, optional **ignore** rules (e.g. skip `*.tmp`), and optional **notify me** when something new was imported.  
- **Activity:** A small **“Watched folders”** area (or entry under **Imports**) shows **folder name**, **status** (watching / paused / unavailable on this device), **last file processed**, and **errors** (e.g. file locked, unsupported type).  
- **Platform honesty:** If **continuous** background watching isn’t possible, the UI says **“We’ll scan for new files when you open the app”** (or on a schedule) instead of implying silent 24/7 monitoring.  
- **Same outcomes** as §5.2.2: each new file is **ingested automatically** and appears in **import activity** with **Done** / **Needs attention**; the user can **fix or roll back** per file after the fact.

### 5.2.4 Keeping a copy of the scan for later (optional)

- After the important details from a document are **stored** (for example **driver license**, **passport or other photo ID**, **vaccination record**, **insurance card**), the app can ask whether to **keep a copy of the scan or file** on the device—not just the typed-out fields.  
- Plain-language choices might look like: **“Save the extracted information only”**, **“Also keep a copy of this scan for uploads”**, or **“Don’t keep the image—only the text.”** Defaults should favor **privacy and smaller storage** unless the user explicitly wants retained copies for **common upload** situations.  
- The user can **change their mind later** from that person’s profile: **remove the image but keep the text**, **replace the scan**, or **delete everything** for that document.

### 5.3 If something is unclear

- The app asks **one question at a time** instead of showing a blank error.  
- Example: “We’re unsure about this date—does it look right to you?”

### 5.4 Same document type, newer scan or file

- When the user already has, say, a passport on file and adds another **scan or upload** labeled the same way, the flow includes: **Replace previous passport details** vs **Keep both** (for example old and new passport overlapping briefly).  
- Choosing **Replace** moves the old values into **history** (section 4.5) and makes the new confirmation the **main** passport details.  
- If they **kept a saved scan** for uploads, **Replace** can also update **which file** is used for “attach document” flows—**never** without confirming.

### 5.5 Using saved scans when a form asks for an upload

- On websites that ask for **“upload a copy of your ID”** or **“attach vaccination proof,”** the helper can offer **“Choose from your saved documents”** when a matching **kept scan** exists—so the user doesn’t have to search the camera roll again.  
- The user still **confirms** which document to attach; the site’s rules (file type, size) are respected with a short message if something needs to be **trimmed** or **exported differently** (product-defined).  
- Nothing is sent to a company server **to perform** the attachment; the file stays on the device until the **browser or site** receives it the same way as any normal upload.

---

## 6. Browsing everything you’ve stored

### 6.1 “Everything at a glance”

- A **read-friendly** view: organized the way you’d think about family—by person—rather than by abstract categories.  
- Optional **filter**: by person, by topic (school, health, etc.), or “needs review”—always in everyday language, not system-style lists.

### 6.2 Saved document copies (when the user opted in)

- Under each person, a clear area for **documents you chose to keep as files**—for example **Driver license**, **Passport**, **Vaccination record**—with **date**, and actions: **View** (after unlock), **Replace scan**, **Remove file only**, **Remove details and file**.  
- Helps people find **what to attach** without mixing personal scans with random photos in the gallery.

### 6.3 Deleting or cleaning up

- **Delete one field** — Quick, with undo if available.  
- **Delete everything for one person** — Strong warning; type a short confirmation if the product policy requires.  
- **Export** (if offered) — Explains in one sentence what will be included and that it stays **under the user’s control** (e.g. saved to a folder they choose).

---

## 7. Filling forms: three scenarios (computer, tablet, phone)

The product is built so people can use **the same saved information** whether they’re on a **desktop browser**, a **tablet**, or a **phone**—and whether the form is **on the web** or **inside another app** (on tablet and phone). It always makes clear **which household member** that information belongs to before it helps fill the form (section 7.2).

### 7.1 First-time setup: the Chrome add-on and the app

- The user installs a **small add-on for Chrome** from the normal browser add-on store.  
- During setup, the device also gets the **companion app** (or an update to it) so the add-on has a **safe partner** on the same machine—where the family information actually lives.  
- Short onboarding explains: **the add-on does not store your family details in the browser**; it asks the **app on your device** when you want help.  
- If the user prefers **not** to use Chrome for a particular task, they can still **open a link inside the companion app**—same review and help, different entry point.

### 7.2 Whose information is this form using?

- A household may have **several people** on file (you, a partner, children, others). The app needs to know **which person’s details** to use—otherwise it might put the wrong child’s name or the wrong ID on an application.  
- When the user asks for help with a form, the app **asks first** if it isn’t obvious—for example: **“Who is this form for?”** with choices like **Me**, **My partner**, **Alex**, **Sam**, or another **named member** of the household.  
- Sometimes the app may **suggest** a person (for example if the page title matches a child’s name), but the user should **confirm** before anything is filled—especially when there are **several children**.  
- A clear line stays on screen while helping—**“We’re using details for: Alex”** (or similar)—with **Change** if the user realizes they picked the wrong profile.  
- Saving or updating information at the end of the session (section 8) always applies to **whoever** was selected for this form, unless the user switches profile mid-flow and confirms.

### 7.3 What works the same in Chrome (desktop, tablet, and phone)

- The add-on **notices when the page is really a form** (boxes to fill, questions to answer). **Only then** it can offer to help—on ordinary reading pages it **stays quiet**.  
- When it is a form, the user can choose to **fill from saved information**, step through **review**, or use **gentle next-step hints**—without the product **taking over** the page.  
- **Chrome’s own autofill** and **password managers** keep working as usual. If the user is using those, our help **does not push in front** or fight for the same boxes—our options appear when **the user asks** for them, or in a way that **doesn’t block** built-in suggestions.

### 7.4 On a desktop or laptop

- The user opens **Chrome** and goes to any site as they normally would.  
- When they reach a **form**, the add-on can connect to the companion app and **offer** to fill from what’s saved—**review first** or **go ahead with fewer stops**, depending on what they pick.  
- The page still **looks and behaves like the real website**; verification codes and confirmations happen **right there** in the tab.

### 7.5 On a tablet

- **In Chrome:** the same experience as on a computer (sections 7.1–7.4), adjusted for touch and screen size.  
- **In other apps** (for example a bank or benefits app that shows its own screens): when supported, the product can also **help fill that app’s form** from the same saved information, using the same **review** and **respect for the user’s pace**—without asking for family data to be stored on a server.

### 7.6 On a phone

- **In Chrome:** again the **same** add-on behavior—compact controls, clear taps, no clutter on tiny screens.  
- **In other apps:** same goal as the tablet—**forms inside apps** can get help **when the platform allows** and when the product supports that app or flow.

### 7.7 While you fill (any of the scenarios above)

- A **small helper** stays available: **See what will be filled**, **Pause**, **Need help**, and—when something is missing from saved information—**Scan a document** or **Add from gallery / files** (often via the companion app or a handoff that keeps context).  
- **When saved information doesn’t cover everything the form needs:** the product **calls this out** in plain language—for example **“We don’t have a mailing address on file for Alex”** or **“These items are still empty”**—and invites the user to **type or paste** what’s missing **before** continuing, instead of leaving blanks without explanation.  
- **Review** (when chosen): a clear comparison of **what we have saved** and **what will go into each box**; **edit** before continuing; offer to **save for next time** (see section 8).  
- If the page asks for a **file** or **photo upload**, and the user has a **matching saved scan**, offer to **attach it from saved documents** (section 5.5).  
- **Codes by text or email:** the user still **types the code on the real form or screen**; we only **highlight** or **explain** where it goes—never pretend to read messages for them.  
- If something **can’t** be matched automatically: **here’s the value—copy it** and **move to the next field**—no dead ends.

---

## 8. Updating information during a form (and saving for later)

The app does **two** different things when the user asks to keep form work in **local memory**:

- **Update** what was **already saved**—replace the old stored value with what they typed or corrected on the form (still their device, still their choice).
- **Add** what was **never saved before**—save new fields or details for the first time.

Both require a **clear yes** from the user (or **decide later**), never a silent overwrite.

### 8.1 When the user changes something we already had on file

- When information was **filled from saved memory** (or shown in review) and the user **changes** it—because the website asked for something slightly different, or because they noticed an error—a prompt should make the distinction clear, for example:  
  **“Update what we keep on file for [name] to match what you entered?”** — **Yes / No / Decide later**.  
- **Yes** **updates** the local profile: the **same** logical field(s) in the database are **written with the new value** so the next form starts from the corrected information. Where the product keeps **history**, the previous value may move into the **past** list (see section 4.5).  
- **No** leaves **on-file** data unchanged; only this form session uses the new text.  
- **Decide later** dismisses until the end of the session, then asks once more before closing.

### 8.2 When something was missing from saved information and the user fills it in

- If the form needed details **not** already in memory, the user **enters them** during the session (or adds them via scan/upload, then confirms).  
- After that, the product asks whether to **keep** those details for the future—for example: **“Save this to your profile for Alex so you don’t have to type it again?”** — **Yes / No / Decide later**.  
- **Yes** **adds** those details into the household information for that person (and topic, if the product uses topics)—a **new** or first-time save for those fields.  
- **No** uses the values **only for this form**; they are not kept as ongoing memory unless the user changes their mind before closing (policy-dependent).  
- **Decide later** can mean **ask again at the end of the form** or **once before leaving**, so people aren’t interrupted on every single line during a long application.  
- For **very sensitive** items (for example full ID numbers), the product may **ask twice** or default to **“don’t save”** unless the user clearly opts in—so saving is **deliberate**.

---

## 9. Sharing with someone nearby (household or trusted helper)

### 9.1 Who can share and what

- From a **person’s page** or from **Share** on Home: **Choose people**, **choose topics or fields** (e.g. only school-related, only contact), **set how long** access should last (end date or number of days).  
- Plain language: **“They will only receive what you select, until the time you set.”**

### 9.2 Choosing the other device

- **Nearby sharing** — Shows devices **close by** the way the phone or computer already does for photos (same mental model).  
- **Confirmation** — Both sides see **who is sending** and **who is receiving**; a short code can appear so nobody accepts the wrong neighbor by mistake.

### 9.3 On the receiving side

- **Accept** — Short summary of what will be imported and until when.  
- After import, new information appears **labeled** as shared: **“Received from [name], valid until [date].”**

### 9.4 Managing active sharing

- **Outgoing** — List of what you’ve shared, with whom, until when; **Stop sharing** for any item.  
- **Incoming** — What you’ve received from others, with the same clarity.

*The experience stresses: **you chose the scope**, and **it went straight to the other device when they were beside you**—not stored on a company server for them to download later. Everyday tips in onboarding reinforce this in plain language.*

---

## 10. Settings & help

### 10.1 Settings

- **Account** — Sign out, change password, email.  
- **App lock** — Optional extra PIN, fingerprint, or face check when opening the app.  
- **Backups & devices** — Short, honest notes: what stays only on the device vs what the user might choose to back up using their own system—**no jargon**.  
- **Privacy** — A short page: what **never** leaves your device as family information; what **might** be needed only for your account or to improve the product in a general way (in words anyone can follow).

### 10.2 Help

- **Short answers** to: Is my data on your computers? How do I share with my partner? What if a form doesn’t fill? How do I install the Chrome add-on and the app?  
- **Contact** — How to reach support without pasting private details into email by mistake (guidance only).

---

## 11. Messages & tone across the app

- **Calm** — Fewer exclamation points; more reassurance.  
- **Specific** — “We couldn’t fill this box” beats “Error 12.”  
- **Honest** — When something is manual (codes, tricky websites), the app says so and **stays helpful**.

---

## 12. One-page journey map (example)

1. Sign in → 2. Add the **Chrome add-on** and the **companion app** → 3. Add “Mom,” “Dad,” “Alex” → 4. **Scan** a school enrollment letter (or **upload** a photo you already had) → 5. Confirm suggested fields → 6. Open the school district site **in Chrome** → 7. When the add-on sees the form, choose **Review** → 8. A needed field isn’t saved yet—**enter it**, then **choose whether to save for next time** → 9. Adjust Alex’s grade → **Save for next time** → 10. Enter the verification code on the site when it arrives → 11. Submit → 12. Later, **Share** only Alex’s school fields with Dad’s tablet **until Sunday** → 13. Dad accepts nearby → Done.

This map is **one possible week**—the product should feel natural whether the user only does step 5 once or repeats variations all month.

---

*This document is meant to guide design and copy. It can be paired with visual wireframes when the team is ready.*
