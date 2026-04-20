# ADR 0016: Extension ↔ host messaging: framed JSON-RPC–style envelope, pairing, and threat model

## Status

Accepted

## Date

2026-04-19

## Context

ADR 0007 requires **Manifest V3** and **native messaging** between the browser extension and a **local host** that owns the Rust core and SQLite. We need:

- A **versioned wire format** that can evolve without breaking clients.
- Clear **authorization**: not every process on the machine may invoke vault operations.
- A documented **threat model** so engineers do not mistake “local” for “trusted.”

**Transport (browser-defined):** Chromium **Native Messaging** uses a **binary framing** on stdin/stdout between the extension and the host: a **4-byte little-endian unsigned integer** length prefix, followed by **UTF-8 JSON** of that length (see Chromium docs: *Native Messaging*). **Firefox** uses the same framing for native messaging. Our **application payload** lives inside that JSON.

## Decision

### Wire format (inside the OS pipe)

1. **Framing**: Follow the **Chromium native messaging** rule: host and extension read/write messages as **`uint32` length + UTF-8 JSON body** (no newline delimiter in the binary framing layer).
2. **Envelope** (every request and response body is one JSON object):

| Field | Type | Purpose |
|--------|------|--------|
| `jsonrpc` | string | Always `"2.0"` (subset compatible with JSON-RPC 2.0). |
| `id` | string \| number \| null | Correlates request/response; server echoes for success/error. Notifications may use `null` id only if product allows fire-and-forget (default: **always use ids**). |
| `method` | string | Namespaced method, e.g. `vault.fill.getCandidates`. |
| `params` | object | Method arguments; **never** include raw secrets in logs. |
| `error` | object | Present on failure: `{ "code": int, "message": string, "data": optional }`. |
| `result` | object | Present on success. |

3. **Versioning**: `params` **must** include `"apiVersion": 1` (integer) until a breaking change increments it; hosts **reject** unsupported versions with a defined error code.

4. **Batching**: Avoid batching multiple logical operations in one JSON blob for v1—keeps auditing and cancellation simple. Revisit in a later ADR if needed.

### Authorization and session model

- **Extension identity**: The host allows connections **only** from the **registered extension ID** (and on Firefox, the add-on ID) configured at install; configuration is **not** user-editable in production builds except via developer mode.
- **User session / capability token**: High-risk methods (`fill.apply`, `export`, `share.initiate`) require a **`sessionId`** obtained after **explicit user unlock** (biometric / app PIN) in the host within a **short TTL** (e.g. 5–15 minutes, product-tuned). The extension passes `sessionId` in `params`; the host **validates** before touching secrets.
- **Single-user desktop**: Bind the host to **one OS user**; reject cross-user pipes.

### Threat model (minimum)

| Threat | Description | Mitigation (best effort) |
|--------|-------------|---------------------------|
| **T1 Malicious web page** | Page JS tries to talk to the host directly. | **Not possible** via web APIs; only the **extension** has the native messaging port. Content scripts must not expose a bridge to arbitrary page JS beyond tightly scoped, user-gesture-gated actions. |
| **T2 Malicious or compromised extension** | Malware replaces the extension or uses stolen extension ID. | **Store signing**, **auto-update** from official channels, **host checks** extension ID; **least-privilege** methods; **user-visible** actions for bulk export; **rate limits** on fill APIs. **Cannot fully eliminate** if the attacker controls the extension binary—treat as **high impact**, **defense in depth**. |
| **T3 Local malware (non-extension)** | Another process pretends to be the browser or opens the host binary. | Host **does not** expose a generic localhost HTTP server for vault by default; native messaging is **spawned by the browser** with inherited pipes—malware must subvert the browser or the host binary. Optional **mutual authentication** (host verifies launch parent PID / platform-specific attestation) is **wish-list**, not MVP gate. |
| **T4 Shoulder surfing / unlocked session** | Attacker uses PC while user is away. | **App lock**, **short session TTL**, **lock on sleep**; sensitive operations require re-auth. |
| **T5 Clipboard / DOM exfiltration** | Values copied to malicious pages. | **User-invoked** fill; **clear clipboard** policy optional; **field scope** limits per method. |

### Logging

- **Never** log `params` or `result` fields that contain **PII** or **secrets** at default log levels.
- Debug builds may log **method names** and **correlation ids** only.

## Consequences

**Positive**

- One **parseable** contract for extension and host engineers; JSON-RPC shape is familiar and tool-friendly.
- Explicit **threat table** avoids false confidence in “local = safe.”

**Negative**

- JSON parse cost per message—acceptable at form-fill cadence; binary protobuf could be a later optimization (would need a new ADR).
- **Session / pairing UX** adds friction; must be tuned for usability.

**Follow-ups**

- OpenAPI-style **schema files** for each `method` checked in CI (optional code generation for TypeScript extension).
- **Firefox / Safari** packaging differences documented in implementation guide, not duplicated here.
