# ADR 0003: Shared native core library across mobile, desktop, extension host

## Status

Accepted

## Date

2026-04-19

## Context

We need **feature parity** across:

- Mobile app (primary capture and SQLite).
- Optional desktop companion (folder watch, heavier batch jobs).
- Browser extension (DOM access only in the browser; secrets and DB should live outside the extension sandbox).

Duplicating pipelines (OCR orchestration, crypto, DB, LLM runtime) in Kotlin, Swift, and TypeScript increases defect rates and drift.

## Decision

Implement a **shared native core** in **Rust** (see ADR 0013; C++ only at thin SDK boundaries) that owns:

- Cryptography and proximity session protocol.
- SQLite access, migrations, and repository-style APIs.
- Ingestion pipeline orchestration (OCR adapters, parsers, validators).
- LLM invocation where the runtime is native (ONNX / llama.cpp–class stacks).
- Provenance and audit append paths.

Expose a **narrow FFI surface** to:

- **Android** (JNI / NDK) and **iOS** (C ABI / Swift bridging).
- **Desktop** host for the extension (**native messaging**).

The **browser extension** remains thin: DOM extraction, UX, and IPC to the host; it does **not** own the canonical database.

## Consequences

**Positive**

- One implementation of security-sensitive and schema-sensitive logic.
- Easier reasoning about compatibility across surfaces.

**Negative**

- Higher upfront investment in build systems (mobile FFI, signing, reproducible builds).
- UI layers still require native or cross-platform UI choices; this ADR does not mandate Flutter vs native UI.

**Follow-ups**

- **LLM runtimes** per platform: document in implementation spec or a future ADR when hardware targets are fixed.
