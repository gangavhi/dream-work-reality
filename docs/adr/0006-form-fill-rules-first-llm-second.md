# ADR 0006: Form-fill intelligence: rules and saved mappings first, LLM second

## Status

Accepted

## Date

2026-04-19

## Context

Web forms expose inconsistent cues (labels, placeholders, `name`/`id`, ARIA). LLMs can guess well but are slower, costlier on-device, and risk leaking context into logs if mishandled. Users also repeat the same sites; learning mappings is high leverage.

## Decision

Use a **two-tier matcher**:

1. **Deterministic tier**: saved **site + field fingerprints** (`FormProfile`), synonym tables, type detectors (regex + small ONNX classifiers where useful), and explicit user overrides.
2. **LLM tier**: only for **ambiguous** fields or first-time sites, consuming **minimal** context (clustered label text + field metadata), outputting **references** to DB values rather than embedding secrets in unstructured text.

Additional rules:

- **Never auto-submit**; treat OTP and payment fields with **deny-by-default** or explicit unlock.
- Extension receives **candidate values** from the local host over IPC, not by scraping cloud APIs.

## Consequences

**Positive**

- Better latency and repeatability on high-traffic portals.
- Smaller on-device model invocations and easier testing of the deterministic path.

**Negative**

- `FormProfile` storage needs **versioning** when site DOMs change; stale profiles degrade until refreshed.
- Fingerprint stability across DOM changes is an ongoing engineering cost.

**Follow-ups**

- Telemetry (opt-in) on match tier usage and user corrections to improve rules.
- **Small ONNX classifiers** (tier 1) and **LLM tier** backends: **ADR 0017**.
