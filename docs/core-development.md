# Core development (Rust + HTTP demo)

This guide describes **how to build, test, and extend** the shared native core and the Axum demo API. It complements [`architecture.md`](architecture.md) and the ADR index [`adr/README.md`](adr/README.md).

---

## 1. Layout

| Path | Purpose |
|------|---------|
| [`core/dreamwork_core`](../core/dreamwork_core/) | Static library + `rlib`: SQLite (`rusqlite` bundled), migrations + **`schema_change_log`**, FFI, OCR/inference seams, crypto + proximity primitives (**ADR 0009 / 0014 / 0017**) |
| [`core/dreamwork_uniffi`](../core/dreamwork_uniffi/) | **`cdylib`** UniFFI surface mirroring key FFI flows for Kotlin/Swift bindings (**ADR 0013**) |
| [`core/core_api`](../core/core_api/) | **Binary** `core_api`: Axum routes for health + manual-entry demo |
| [`integration/`](../integration/) | Extension JSON-RPC fixture validation (Python stdlib) |

Platform UI (Swift; Kotlin later) links **`libdreamwork_core.a`** built from `dreamwork_core` (see [`apps/ios/project.yml`](../apps/ios/project.yml)). UniFFI-generated bindings can target the **`dreamwork_uniffi`** artifact instead of raw C strings where convenient.

---

## 2. Commands

From [`core/`](../core/):

```bash
cargo fmt --all
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace --locked
```

**ONNX Runtime integration tests** (downloads ORT via `ort`; enables `tls-rustls`):

```bash
cargo test -p dreamwork_core --features onnx --locked
cargo clippy -p dreamwork_core --all-targets --features onnx -- -D warnings
```

Focused:

```bash
cargo test -p dreamwork_core
cargo test -p core_api
cargo test -p dreamwork_uniffi
```

**MSRV:** Declared in [`core/dreamwork_core/Cargo.toml`](../core/dreamwork_core/Cargo.toml) as `rust-version`.

---

## 3. Testing strategy

| Layer | What runs | Intent |
|-------|-----------|--------|
| **Unit tests** | `#[cfg(test)]` modules beside code | Domain logic: matchers, validators, SQLite writes |
| **Integration tests** | [`core/dreamwork_core/tests/`](../core/dreamwork_core/tests/) | Disk-backed SQLite, migrations, cross-module pipeline smoke |
| **HTTP tests** | [`core_api`](../core/core_api/) `lib.rs` `#[cfg(test)]` | Router handlers with `tower::ServiceExt::oneshot` |
| **Extension protocol** | [`integration/`](../integration/README.md) | Schema subset validator + unittest discovery |
| **iOS** | `xcodebuild test` (macOS) | Swift ↔ FFI wiring; see [`apps/ios/README.md`](../apps/ios/README.md) |

FFI entrypoints are covered by **Rust unit tests** that exercise the C ABI from the same crate (singleton repository).

---

## 4. Modules (production seams)

- **`db`** — [`apply_core_migrations`](../core/dreamwork_core/src/db/migrate.rs), [`schema_change_log`](../core/dreamwork_core/src/db/migrate.rs), [`apply_adhoc_ddl`](../core/dreamwork_core/src/db/migrate.rs) for transactional DDL auditing (**ADR 0005**).
- **`memory`** — [`EntryRepository`](../core/dreamwork_core/src/memory/mod.rs), [`SqliteEntryRepository::open_encrypted`](../core/dreamwork_core/src/memory/sqlite.rs) with optional **`sqlcipher`** feature (`PRAGMA key`).
- **`crypto`** — HKDF + ChaCha20-Poly1305 helpers for vault blobs (**ADR 0014** wire-up path).
- **`proximity`** — X25519 handshake structs + transport trait (**ADR 0009**).
- **`ocr`** — [`OcrEngine`](../core/dreamwork_core/src/ocr/mod.rs); native adapters serialize JSON into **`dreamwork_ocr_apply_normalized_json`** (Vision iOS sample under [`VisionOcrAdapter.swift`](../apps/ios/DreamWorkApp/Sources/Core/VisionOcrAdapter.swift)); Android notes in [`android/mlkit-ocr-adapter.md`](android/mlkit-ocr-adapter.md).
- **`inference`** — [`OnnxInferenceSession`](../core/dreamwork_core/src/inference/mod.rs) stub + **`OrtIdentityOnnxSession`** behind **`onnx`** feature; [`parse_gguf_header_prefix`](../core/dreamwork_core/src/inference/gguf.rs) for GGUF container inspection (**full llama.cpp-class inference remains platform-shim work per ADR 0017**).
- **`runtime`** — Shared singleton backing FFI + UniFFI exports (manual entries + last OCR JSON snapshot).
- **`ffi`** — C ABI; **must not panic** across the boundary.
- **`schema`**, **`form`**, **`provenance`**, **`ingestion`** — Continue to grow with persistence wiring.

Pinned GGUF / ONNX filenames: [`device-matrix.md`](device-matrix.md).

---

## 5. SQLCipher linkage

- Crate feature **`sqlcipher`** only toggles calling **`PRAGMA key`** before migrations—**stock `rusqlite/bundled` SQLite ignores encryption**.
- Ship builds must link **SQLCipher** (CocoaPods / Gradle `sqlcipher`, custom `libsqlite3`) and typically **disable** `bundled` sqlite for that flavor—this repo keeps bundled SQLite for CI portability; wire SQLCipher in Xcode/Gradle as a follow-on packaging step.

---

## 6. ONNX fixture regeneration

The tiny Identity graph lives at [`core/dreamwork_core/fixtures/identity.onnx`](../core/dreamwork_core/fixtures/identity.onnx). Regenerate with:

```bash
python3 scripts/gen_identity_onnx_fixture.py
```

(requires `pip install onnx`).

---

## 7. UniFFI bindings

[`dreamwork_uniffi`](../core/dreamwork_uniffi/) exports `dw_*` helpers. Generate Swift/Kotlin scaffolding with **`uniffi-bindgen`** from your installed toolchain (see [UniFFI docs](https://mozilla.github.io/uniffi-rs/)); keep generated artifacts out of this repo until build pipelines stabilize.

---

## 8. CI

GitHub Actions [`.github/workflows/ci.yml`](../.github/workflows/ci.yml):

- **Rust:** `fmt`, `clippy -D warnings`, `cargo test --workspace --locked`
- **`dreamwork_core` + ONNX:** `cargo test -p dreamwork_core --features onnx --locked`
- **Supply chain:** [`cargo-deny`](https://embarkstudios.github.io/cargo-deny/) against [`core/deny.toml`](../core/deny.toml) + **`cargo audit`** on [`core/Cargo.lock`](../core/Cargo.lock)
- **iOS:** **`macos-latest`** — `brew install xcodegen`, `xcodegen generate`, `xcodebuild test` with the first available **iPhone** simulator (Rust pre-build script builds `aarch64-apple-ios-sim`)
- **Integration protocol:** `validate_protocol.py` + `unittest`

Local parity:

```bash
cd core && cargo deny check
cd core && cargo audit
```

---

## 9. Operational notes

- **Cargo.lock:** Committed under [`core/Cargo.lock`](../core/Cargo.lock); CI uses `--locked`.
- **`ort` + `ndarray`:** Feature **`onnx`** adds an explicit optional **`ndarray`** dependency so Cargo merges **`std`** features required by `ort`'s ndarray helpers.
- **Model upgrades:** Follow [`device-matrix.md`](device-matrix.md) Section 4.3.3 when changing GGUF pins.
