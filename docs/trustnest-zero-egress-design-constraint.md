# TrustNest zero-egress design constraint

**Product:** TrustNest (DreamWork / Nest Ledger companion app)  
**Status:** Accepted product constraint — all new features must comply  
**Related ADRs:** [0001](adr/0001-local-first-no-document-upload-by-default.md), [0009](adr/0009-proximity-sharing-ble-secure-channel-time-bound-grants.md), [0010](adr/0010-optional-backend-metadata-only.md), [0017](adr/0017-on-device-inference-runtimes-per-platform.md)

---

## 1. The promise (marketing and engineering)

> **Your data stays on your device.**  
> TrustNest does **not** send household identity, document images, OCR text, extracted fields, or form-fill payloads over the internet to fulfill product use cases.

This is the primary trust differentiator. Engineering, QA, legal copy, and App Store privacy labels must remain aligned with it.

---

## 2. What “zero egress” means in practice

### 2.1 Forbidden by default (use-case fulfillment)

The following must **never** leave the device as part of normal product behavior:

| Category | Examples |
|----------|----------|
| **Document content** | Photos, PDF bytes, scans, imports from gallery/folder |
| **OCR output** | Raw text, bounding boxes, layout JSON |
| **Structured extraction** | Field maps, document type, issuer region, SSN/passport/DL numbers |
| **Local database** | SQLite rows, exports containing PII, retained scan files |
| **Form assist** | DOM field descriptors paired with values to fill |
| **Model inference input/output** | Prompts containing OCR text sent to a **remote** LLM or API |

If a feature **requires** network access to work, it is **out of scope** unless explicitly exempted below or covered by a new ADR with user-visible consent.

### 2.2 Allowed network (non–use-case / metadata only)

Per [ADR 0010](adr/0010-optional-backend-metadata-only.md), limited internet use is permitted **only** for:

- **Account** — sign-in, device registry, session tokens (no document payload).
- **Opt-in anonymous telemetry** — version, crash buckets, feature flags (no OCR text, no field values).
- **Signed model or app updates** — optional **user-approved** download of **on-device** model weights (artifact bytes land in app sandbox; inference still runs locally).

Account and telemetry must be **architecturally separable** from the ingest and form-fill pipelines so a misconfiguration cannot accidentally attach document content to those channels.

### 2.3 The single intentional exception: proximity sharing

Household data may be transferred to **another user device** the grantor explicitly selects, via **proximity** (NFC tap and/or BLE session per [ADR 0009](adr/0009-proximity-sharing-ble-secure-channel-time-bound-grants.md)):

- Payload is **encrypted end-to-end** between devices; **no product-server relay** of grant content.
- Grants are **time-bound**; shared data on the receiver **expires** and is removed per grant TTL (and revocation).
- Scope is **least-privilege** (selected people, fields, or tables)—not a full vault dump unless the user explicitly chooses that scope.

NFC (or QR for short pairing codes) may bootstrap a session when BLE is flaky; the **security property** is proximity + explicit grant + expiry, not which RF layer completed the handshake.

---

## 3. On-device models are mandatory

All intelligence needed to deliver core use cases must run **on the user’s device**:

| Capability | Requirement |
|------------|-------------|
| **OCR** | Platform engine (Apple Vision, Android ML Kit) or alternate **bundled** engine ([ADR 0004](adr/0004-on-device-ocr-with-pluggable-engines.md)) |
| **Document type detection** | Heuristics, ONNX classifiers, and/or **local** generative model—no cloud classification |
| **Field mapping / schema inference** | Constrained **local** LLM ([ADR 0005](adr/0005-schema-inference-constrained-llm-and-transactional-ddl.md), [ADR 0017](adr/0017-on-device-inference-runtimes-per-platform.md)) |
| **Form-fill matching** | Rules and profiles first; **local** LLM only for ambiguity ([ADR 0006](adr/0006-form-fill-rules-first-llm-second.md)) |

**Paid or commercial models are acceptable** only when:

1. License allows **on-device redistribution** or user-owned download into app storage.
2. Inference runs **entirely offline** after install (no runtime API calls to vendor cloud).
3. Weights are **version-pinned** and recorded in `extraction_run` / model manifest ([device matrix](device-matrix.md)).

**Not acceptable** for production default paths:

- OpenAI / Anthropic / Google Document AI / Azure Form Recognizer **for document understanding**.
- “Bring your own API key” cloud completion during scan review **without** a prominent “data leaves device” warning and **off-by-default** policy.
- Apple **Private Cloud Compute** or any **server-side** vision/LLM for ingest (violates the promise even if Apple-hosted).

---

## 4. Architecture checklist for new features

Before merging any feature that touches documents, profiles, or sharing:

1. **Data flow diagram** — show every byte path; mark anything that crosses the network.
2. **Model manifest** — list artifact IDs, sizes, licenses; confirm inference has **no** runtime URL to vendor.
3. **Failure mode** — if the local model is unavailable, degrade to **heuristics + user edit**, not silent cloud fallback.
4. **Settings audit** — no hidden “cloud enhance” toggles defaulting on.
5. **Logging** — no OCR text or field values in OS logs, crash reports, or analytics.
6. **Sharing** — if data leaves the device to another phone, document grant scope + TTL in UX and storage layer.

---

## 5. Current implementation gaps (honest baseline)

The **target** is zero egress. **iOS enforcement (May 2026):**

| Path | Status |
|------|--------|
| `ZeroEgressPolicy` | **Shipped** — blocks public-internet LLM endpoints; allows loopback + private LAN only |
| `GenAISettings` | **Shipped** — default **Off**; cloud provider removed from Release builds |
| `GenAIFieldMapper` | **Shipped** — refuses HTTP when endpoint fails policy; degrades to heuristics |
| `CoreIngestHTTPClient` / `CoreAPISync` | **Shipped** — DEBUG-only localhost `core-api` sync; disabled in Release |
| `DevAPIKeyStore` | **Shipped** — DEBUG-only; no API keys in Release |
| Bundled on-device GGUF | **Partial** — Rust `local_document_mapper` + FFI shipped; optional GGUF install path + header validation; full llama.cpp inference TBD |
| Optional **account / telemetry** backend | **Planned** — must stay metadata-only ([ADR 0010](adr/0010-optional-backend-metadata-only.md)) |

**OCR itself** (Apple Vision via `OcrEngine` / `VisionOcrAdapter`) satisfies zero egress.

See [document-intelligence-deep-dive.md](document-intelligence-deep-dive.md) for ingest strategy: **general-purpose on-device extraction** (no per-document templates); accuracy work must stay on-device.

---

## 6. How this connects to other docs

| Document | Role |
|----------|------|
| [document-intelligence-deep-dive.md](document-intelligence-deep-dive.md) | Accuracy roadmap for doc type + fields (on-device only) |
| [device-matrix.md](device-matrix.md) | Which GGUF/ONNX artifacts ship per RAM tier |
| [architecture.md](architecture.md) | Module-level flows |
| [how-secure-is-the-data-locally.md](../how-secure-is-the-data-locally.md) | Encryption and OS data protection |

---

## 7. Decision summary (one paragraph for PRs)

**TrustNest fulfills use cases without sending user content to the internet.** Models run locally; storage is local; form fill reads local memory. The only cross-device transfer is **user-initiated, time-limited proximity sharing**—not cloud sync. Any PR that adds network calls carrying PII must be rejected or blocked behind a new ADR and explicit user consent that TrustNest retail builds do not enable.
