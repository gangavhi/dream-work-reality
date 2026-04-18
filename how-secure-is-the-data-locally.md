# How secure is the data locally?

This document explains **defense layers** for on-device structured memory, how that relates to **“data does not leave the device”** (and **“does not traverse the internet”**), and what **sharing with household members** can and cannot guarantee. It is written for product and engineering alignment—not as a formal security audit.

**Related docs:** `idea-brainstorming.md` (local data plane, **generative structuring**, & offline sharing), `features-list.md` (security baseline & wish list).

---

## 1. Threat model in one page

| Scenario | Realistic goal |
|----------|----------------|
| **Casual access** (unlocked phone left on a table, nosy acquaintance) | Strong: app lock + OS protections often sufficient. |
| **Lost/stolen device** (attacker has hardware, not your passcode) | Strong if **full-disk / file encryption** is on and passcode is good; app-level encryption adds defense in depth. |
| **Malware without root / full sandbox escape** | Moderate to good: OS sandbox + encrypted DB + keys in hardware-backed keystore raise the bar. |
| **Fully compromised device** (root/jailbreak, kernel malware, forensic extraction with credentials) | **No honest app can promise “unhackable.”** Risk is **reduced**, not eliminated. |

**Bottom line up front:** Security is **layered**. The local database should be **hard to read** without authorized user action and **expensive to extract** at scale—but **not** absolute against a determined attacker who fully controls the device and secrets.

---

## 2. Why “data does not leave the device” matters

When structured PII stays **off your product’s servers**, you remove entire classes of failure:

- **Server breach** does not expose household memory (there is no central copy).
- **Insider access** at the vendor is not a path to read user families’ fields.
- **Subpoena / legal process** directed at the vendor does not yield what the vendor never holds—*subject to honest architecture* (see §6).

That is a **strong** privacy and security story. It is **not** the same as “the data is safe from every threat.” Local storage shifts risk to **the device**, **the OS**, **backups**, and **user behavior**.

---

## 3. Mechanisms to protect the local database

Below are **common building blocks** (exact choices depend on platform: iOS, Android, desktop). They stack; none alone is perfect.

### 3.1 OS sandbox and app isolation

- The app’s files live in a **private container** other apps cannot read on a stock, non-jailbroken device.
- **Mitigates:** casual scraping by other apps.
- **Does not mitigate:** OS compromise, rooted devices, or the user’s own backup/export paths.

### 3.2 Full-disk / file-level encryption (device-wide)

- Modern phones encrypt storage at rest; decryption is tied to user authentication (passcode/biometric) depending on settings.
- **Mitigates:** offline imaging of storage from a locked device (when passcode unknown and protections hold).
- **Does not mitigate:** unlocking with **known** passcode, or malware running **after** unlock with user session active.

### 3.3 Application lock (PIN / biometric inside the app)

- Adds a **second gate** before showing sensitive UI or decrypting app-specific keys.
- **Mitigates:** shoulder-surfing, short “unlocked phone” windows, handoff to a child’s game on the same device.
- **Does not mitigate:** malware that hooks UI after the user unlocks the app.

### 3.4 Encryption of the database itself (defense in depth)

- Store the SQLite (or other) DB **encrypted** (e.g. SQLCipher or platform APIs that provide AES-GCM streams), not only “hidden in the sandbox.”
- **Mitigates:** forensic tools that read app files from a backup or in some partial-compromise cases; raises bar for offline file copy exfiltration.
- **Limitation:** the app must still **open** the DB when the user uses the app—keys exist in memory during use; sophisticated malware can target that window.

### 3.4.1 Retained document images and PDFs (upload vault)

When users **opt in** to keeping **scans or files** (e.g. driver license, passport, vaccination card) for **form attachments**, those blobs should live in **app-managed encrypted storage**—same key hierarchy as the database where practical—not as ordinary gallery files unless the user explicitly exports there.

- **Mitigates:** casual browsing of photos after device unlock; backup tools indexing “just another JPEG.”
- **User controls:** **delete file without deleting structured fields** (or vice versa) should be explicit.
- **Backup:** Same tradeoffs as §3.7—excluding large sensitive blobs from device cloud backup may be desirable; communicate clearly.

### 3.4.2 Reading a user-selected folder (batch import)

- The app should only read files **inside folders the user explicitly selects** (or via **multi-file picker** on mobile)—**no** broad disk access without consent.
- **Temporary** read of originals for OCR can be **streamed** or **copied into app sandbox** per policy; **processed on-device**; originals outside the vault are **not** uploaded to your backend.
- **Mitigates:** accidental indexing of unrelated directories—**user intent** is scoped to the chosen path.

#### 3.4.2.1 Watched folders (ongoing read)

If the user enables **watch** on a folder, the app may **repeatedly** read **new or changed** files under that path—still **only** there, still **on-device** processing, still **no** upload of document content to your backend.

- **User control:** **Clear on/off** per watch; **pause** without deleting configuration; **revoke** by removing the watch or the OS permission that granted the path.
- **Surface area:** A watch is **higher** than a one-shot import (more chances to ingest a file the user forgot was there); **mitigate** with **ignore patterns**, **notifications** summarizing what was ingested, and **easy rollback** per file from the review list.
- **Platform:** Background execution limits on mobile may force **rescan-on-open** instead of true 24/7 monitoring—**security** (fewer background file touches) and **UX** (honest expectations) align.

### 3.4.3 Word and Excel files

- **Office** files may contain **macros**; the product should **not execute** them—**data extraction only**—reducing malware surface compared to opening the same file in a full desktop Office suite inside the vault.
- Parsed content stored in the DB follows the same **encryption** posture as other local secrets; **optional** retention of the original `.docx`/`.xlsx` is user-controlled like other **retained document files**.

### 3.4.4 Generative structuring (schema inference)

Structured memory relies on a **generative model** to **infer** field mappings and sometimes **create or alter** database tables locally.

- **Default posture:** Run **inference on-device** so **document text and layout** used for structuring **do not** leave the device for that step—consistent with **“no family PII to the backend.”**
- **If** a future offering used **cloud-based** generative inference, that would be a **separate consent** and threat model: content could transit third-party or vendor-controlled endpoints unless **fully private** contractual and technical guarantees exist—**not** implied by the baseline local-first story.
- **Supply chain:** On-device models still imply **trust in the model artifact** (signed updates, reproducible versioning); **wrong or biased** outputs are a **correctness** risk mitigated by **UI review**, **edit**, and **rollback**, not only by encryption.

### 3.5 Key management: hardware-backed keystore / Secure Enclave

- **Data encryption keys** should be wrapped or derived using **hardware-backed** key storage (Android Keystore, iOS Keychain with Secure Enclave–backed keys where available).
- **Mitigates:** pure software extraction of raw keys from app preferences; brute-force is pushed toward the device’s rate limits and secure hardware.
- **Does not mitigate:** user unlocking the device and unlocking the app while malware observes, or **full compromise** of the running OS.

### 3.6 Minimize sensitive data in memory and logs

- Avoid logging field values, URLs with tokens, or OCR text.
- Clear buffers where feasible; treat **crash reports** as sensitive—scrub or disable detailed capture for vault operations.

### 3.7 Backup exclusion (where platform allows)

- Mark sensitive containers **not** to sync to **cloud device backups** if policy requires “no off-device copy via backup”—understanding that users may still use other export paths.
- **Mitigates:** accidental restoration of a full vault to another account or iCloud/Google backup exposure windows.
- **Tradeoff:** users may lose data if they lose the device—**user education** and **explicit encrypted export** are the balance.

### 3.8 Integrity and tampering (secondary)

- Sign local packages or use **integrity checks** for app binaries (platform features). Helps against **some** tampering—not a substitute for encryption.

---

## 4. “Even if the device gets compromised”

Language matters.

- **Partial compromise** (malicious app without elevated privileges): layered encryption + keystore + app lock often **meaningfully** protect data **if** keys are not extractable and the malware cannot read the unlocked DB.
- **Full compromise** (root, kernel implant, unlocked bootloader with custom OS, forensic tools **with** user cooperation and passcode): an app can be **forced** or **observed** while open; keys and plaintext may be recoverable.

**Honest product stance:** We implement **industry-appropriate** controls so that **typical** theft and **common** malware scenarios are **strongly** defended, and we **do not** claim immunity against nation-state or full-device takeover.

---

## 5. Why remote “no PII” policy reinforces security

When **account APIs** carry only authentication and **optional anonymous telemetry**—and **cannot** accept household payloads by design:

- Attackers gain **less** from compromising your **backend**.
- Users gain **clearer** mental model: **sensitive data stays on device**; **network** is not a path for family fields.

This does **not** automatically secure the phone; it **removes** a major cloud aggregation risk and narrows blast radius.

### 5.1 Browser extension and companion app (form filling path)

When the user fills forms **in Chrome** using the platform’s **browser extension**, the extension is a **thin control layer** in the page; **structured household data** remains in the **companion application** on the same machine. The expected design is:

- **Local-only channel** between extension and companion (native messaging or equivalent)—**not** “fetch profile from our API to fill the form.”
- **No new cloud path** for PII: the extension should **not** receive or cache a full copy of the vault in the browser’s storage beyond what is strictly needed for the current user action (policy should minimize even that).

**Tablet and phone:** the same principle applies: **memory lives in the companion app**; any bridge to **in-app** forms must also avoid shipping payloads through your backend.

Users should still treat **malicious extensions** and **compromised browsers** as risk factors—**official** distribution only, updates, and clear permission scopes.

---

## 6. Sharing with household members: policy-aligned design

The product goal: **structured sharing** that **does not use the internet as the transport** for the payload and **does not relay** shared content through your **backend**.

### 6.1 What “does not travel over the internet” means here

- **Payload path:** The **encrypted package** moves over **proximity/local** transports (e.g. Bluetooth LE discovery + negotiated Wi-Fi Direct / AWDL-like direct link, UWB-assisted pairing, or same-subnet LAN after QR bootstrap)—**not** uploaded to HTTPS endpoints for delivery.
- **Clarification:** Individual devices may still use the internet for **unrelated** traffic; marketing should avoid implying the **phone has no network**. The claim is **about the shared household payload**, not global air-gapping.

### 6.2 Mechanisms that support that policy

| Mechanism | Role |
|-----------|------|
| **No cloud relay by architecture** | Backend APIs do not accept share payloads; there is **nothing** to “download” from your servers. |
| **Peer-to-peer channel** | OS frameworks for nearby transfer (AirDrop-class, Nearby Share–class, etc.) or documented LAN socket after local pairing. |
| **End-to-end encryption of the package** | Payload encrypted with keys established **between devices** (e.g. ephemeral ECDH) so **intermediaries** (even Wi-Fi access points forwarding local frames) see ciphertext on the wire where applicable—not plaintext JSON. |
| **Authentication of peer** | Short code, QR fingerprint, or trusted device enrollment so users don’t send to **wrong recipient** in crowded places. |
| **Least privilege in content** | Grants carry **only selected fields** and **expiry**—smaller blast radius if a device is later lost. |
| **Revocation on sender** | Sender can **invalidate** remaining trust for future rotations (policy-dependent; see limits below). |

### 6.3 What is still true on “each device is highly secure”

Each participant device should apply the **same local stack** (§3): sandbox, encryption at rest, keystore-backed keys, app lock, backup policy. **Sharing does not weaken** the requirement that **received** data is stored **encrypted** in the recipient vault like any other local memory.

### 6.4 Honest limits (recipient device)

- **Expiry** and “remote wipe” of shared data on **another person’s** phone are **not** cryptographically enforceable by the sender unless the recipient OS cooperates at a level apps rarely have. Best practice: **clear UX**, **auto-expire imports** in-app, **minimal fields**, and **user trust** within the household.
- **Forwarding risk:** A recipient could **screenshot**, **copy**, or **export** unless blocked—**policy** and **minimum necessary** scope mitigate, not eliminate.

---

## 7. Summary table

| Topic | Security story |
|-------|----------------|
| **Local DB** | Sandboxed, encrypted at rest, keys in hardware-backed store, optional app lock; strong vs common theft; not absolute vs full compromise. |
| **Retained scans** | Optional files for uploads held in **encrypted app storage** with clear delete; larger impact than text-only if device is lost—**opt-in** design. |
| **No cloud PII** | Removes server-side aggregation risk; shrinks attack surface on your infrastructure. |
| **Offline sharing** | Payload **not** internet-routed through your service; **peer encrypted** + scoped + expiring grants; each device still must protect its own vault. |
| **Browser helper + app** | Extension talks to **local companion** for fills—**not** a cloud profile download; still subject to browser/extension threat model. |
| **Honesty** | Avoid “unhackable”; use **layered controls**, **clear limits**, and **user-visible** settings (backups, exports, shares). |

---

## 8. Suggested user-facing principles (draft)

1. **Your household structured data is not stored on our servers** as part of normal operation.
2. **We encrypt** sensitive local data and **protect keys** using your device’s secure hardware where available.
3. **Sharing** uses **direct device-to-device** transfer for the payload—**not** our cloud—and only sends what **you** select, for **as long as** you set.
4. **In Chrome**, our small add-on works with the **app on your device** to fill forms—your details are **not** pulled from our website for each field.
5. **Saved scans** you chose to keep for uploads stay in **protected storage** on your device—you can **delete** them anytime.
6. **No security is perfect** against a fully compromised or unlocked device while the app is in use—**use a strong device passcode** and keep OS updated.

This document should evolve with **specific** platform choices (iOS/Android/desktop), **penetration test** results, and **legal review**—especially if you market security claims in regulated regions.
