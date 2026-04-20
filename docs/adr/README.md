# Architecture Decision Records (ADRs)

**See also:** [Architecture diagrams and module guide](../architecture.md) (high-level + per-module technical and layman explanations).

This folder records **significant, stable** architecture choices for the Dream Work Reality platform. Each ADR follows a short Nygard-style template: context, decision, consequences.

| ADR | Title |
|-----|--------|
| [0001](0001-local-first-no-document-upload-by-default.md) | Local-first storage; no document upload by default |
| [0002](0002-sqlite-encrypted-canonical-store.md) | SQLite as canonical on-device relational store |
| [0003](0003-shared-native-core-across-surfaces.md) | Shared native core library across mobile, desktop, extension host |
| [0004](0004-on-device-ocr-with-pluggable-engines.md) | On-device OCR with a pluggable engine abstraction |
| [0005](0005-schema-inference-constrained-llm-and-transactional-ddl.md) | Schema inference via constrained LLM output and transactional DDL |
| [0006](0006-form-fill-rules-first-llm-second.md) | Form-fill intelligence: rules and saved mappings first, LLM second |
| [0007](0007-browser-extension-mv3-native-messaging.md) | Browser extension: Manifest V3 and native messaging to local app |
| [0008](0008-provenance-and-field-value-history.md) | Provenance and append-oriented field value history |
| [0009](0009-proximity-sharing-ble-secure-channel-time-bound-grants.md) | Proximity sharing: BLE discovery, strong session crypto, time-bound grants |
| [0010](0010-optional-backend-metadata-only.md) | Optional backend limited to account and non-content metadata |
| [0011](0011-ingest-write-first-post-ingest-review.md) | Ingest writes first; post-ingest review and sensitive-field gates |
| [0012](0012-first-class-manual-entry-without-documents.md) | First-class manual entry without scans or uploads |
| [0013](0013-rust-for-shared-native-core.md) | Rust for the shared native core (C++ only at SDK boundaries) |
| [0014](0014-sqlcipher-and-os-data-protection-for-at-rest-data.md) | SQLCipher-class DB encryption plus OS data protection |
| [0015](0015-native-mobile-ui-with-shared-rust-core.md) | Native mobile UI (SwiftUI / Compose); Flutter deferred for v1 |
| [0016](0016-extension-native-messaging-protocol-and-threat-model.md) | Extension ↔ host: framed JSON, session model, threat model |
| [0017](0017-on-device-inference-runtimes-per-platform.md) | On-device inference: ONNX Runtime + llama.cpp-class LLM per platform |

**Status values:** `Proposed`, `Accepted`, `Superseded` (with pointer to replacement ADR).

**How to add an ADR:** copy the nearest numbered file, increment the number, set status to `Proposed`, and link superseded ADRs in both directions when replacing a decision.
