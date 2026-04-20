# ADR 0010: Optional backend limited to account and non-content metadata

## Status

Accepted

## Date

2026-04-19

## Context

Some product features benefit from lightweight internet services: **account**, **device list**, **push notifications for non-sensitive events**, or **opt-in telemetry**. This must not contradict ADR 0001’s default boundary.

## Decision

If a backend exists, it stores **only**:

- Authentication identity and **device registry** (public keys, app version).
- **Opaque** references to user-triggered jobs that do not include document bytes (for example “export job ready” without payload).
- **Explicitly anonymous** operational metrics when users opt in.

It does **not** store OCR text, extracted JSON, SQLite dumps, or form field values **by default**. Any future **E2EE backup** must be a **separate** ADR with explicit user consent and client-held keys.

## Consequences

**Positive**

- Backend compromise does not imply bulk document exfiltration.
- Simpler data-processing agreements for the default architecture.

**Negative**

- Features that “sync everything” are intentionally hard; true multi-device sync likely requires **E2EE** engineering or **manual** export/import.

**Follow-ups**

- If multi-device state is required, add ADR: **CRDT vs snapshot sync**, **E2EE envelope format**, and **conflict resolution** UX.
