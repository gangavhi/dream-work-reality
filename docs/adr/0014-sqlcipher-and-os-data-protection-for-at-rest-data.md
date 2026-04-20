# ADR 0014: SQLCipher (or equivalent page-level DB encryption) plus OS data protection

## Status

Accepted

## Date

2026-04-19

## Context

ADR 0002 requires **encryption at rest** for the canonical SQLite store. Two broad approaches exist:

1. **OS / filesystem-level protection only** (e.g. iOS **Data Protection** classes, Android **file-based encryption**, desktop full-disk encryption): the app uses **stock SQLite**; secrecy relies on the OS blocking other apps and on device lock state.
2. **Application-level database encryption** (commonly **SQLCipher**, or SQLite **Encryption Extension** / compatible APIs): the SQLite **file** is ciphertext unless opened with the key inside the app.

Relying on (1) alone is simpler and avoids SQLCipher licensing/build complexity, but **same-origin** threats differ: backups, logical access after unlock, and **cross-platform** parity are harder to describe uniformly.

## Decision

Use **application-level encryption for the SQLite database** via **SQLCipher** or a **license-compatible fork** with the same API guarantees (hereafter “SQLCipher-class”), **in addition to** normal OS sandbox and data-protection APIs.

- **Key material** is derived or unwrapped **inside** the process and stored using the **OS secure enclave / keystore** (Keychain, Keystore, Credential Manager patterns)—not hardcoded, not only in plist defaults.
- **Large file blobs** (retained scans, PDFs) live **outside** the DB row payload where appropriate; those files use **AES** (or platform file encryption APIs) with keys tied to the same user key hierarchy—exact file layout is an implementation detail, but the **threat model** treats “DB file stolen from backup” as **must not** yield plaintext without keys.

**OS-only encryption without SQLCipher-class** is **not** sufficient as the **sole** protection for the primary SQLite file when we claim “encrypted local database” in product copy—OS protection remains **required defense-in-depth**, not a substitute for ciphertext at the SQLite layer.

## Consequences

**Positive**

- **Consistent story** across iOS, Android, macOS, and Windows: the DB file is not readable as SQLite without the app key.
- Aligns with user expectations for a “vault” metaphor.

**Negative**

- **Build complexity**: SQLCipher-class builds must be wired for every target (or use a well-maintained Rust crate that vendors SQLCipher correctly).
- **Performance**: page-level crypto adds CPU cost; need benchmarks on low-end phones.
- **Licensing**: confirm **SQLCipher** (BSD) or chosen alternative compliance in **NOTICE** files; commercial SEE would require a separate ADR if ever chosen.

**Follow-ups**

- Define **key rotation** and **backup/restore** semantics (export includes re-encryption under user passphrase, etc.).
