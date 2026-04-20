# ADR 0007: Browser extension: Manifest V3 and native messaging to local app

## Status

Accepted

## Date

2026-04-19

## Context

The extension can read the DOM but should **not** be the root of trust for secrets, encryption keys, or the full SQLite database. Browsers restrict persistence, background behavior, and system access under **Manifest V3**.

## Decision

- Ship the extension as **Chrome Manifest V3** (service worker background, content scripts for DOM).
- Use **native messaging** to a **local companion** (desktop and/or mobile bridge) that loads the **shared native core** (ADR 0003) for DB access, crypto, and model runtime.
- **Capability tokens**: short-lived, user-initiated unlock windows for autofill IPC; deny by default.

Firefox/Safari variants are **tracked separately**; they may reuse the same host protocol with adapter packaging.

## Consequences

**Positive**

- Clear trust boundary: secrets live outside the extension sandbox.
- Aligns with store and browser direction on MV3.

**Negative**

- Installation friction (companion app + extension pairing) hurts adoption; onboarding UX is critical.
- Native messaging differs by browser/OS; CI and support matrices expand.

**Follow-ups**

- Wire protocol, JSON-RPC-style envelope, session rules, and threat model: **ADR 0016**. Optional **JSON Schema** per `method` in CI is an implementation follow-up.
