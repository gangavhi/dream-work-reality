# Qwen GGUF Model Installation

**Date executed:** 2026-05-25  
**Model artifact:** `llm.schema.lite.v1`  
**Model repo:** `bartowski/Qwen2.5-3B-Instruct-GGUF`  
**Model file:** `Qwen2.5-3B-Instruct-Q4_K_M.gguf`

## Why This Model

We selected `Qwen2.5-3B-Instruct-Q4_K_M.gguf` because it is a practical iOS-first default:

- Qwen2.5 Instruct follows structured JSON-style prompts well.
- 3B Q4_K_M is small enough for flagship iPhone testing.
- The base Qwen2.5 Instruct family is Apache-2.0.
- The repo already had this artifact name in `apps/ios/DreamWorkApp/Resources/model-manifest.json`.

## Executed Setup

The model was downloaded to the local developer machine, outside git:

```bash
~/Library/Application Support/DreamWork/models/Qwen2.5-3B-Instruct-Q4_K_M.gguf
```

Exact verified values:

```text
bytes: 1929903264
sha256: 9c9f56a391a3abbd5b89d0245bf6106081bcc3173119d4229235dd9d23253f94
gguf_magic: GGUF
gguf_version: 3
tensor_count: 434
metadata_kv_count: 39
```

The app manifest was updated:

```text
apps/ios/DreamWorkApp/Resources/model-manifest.json
```

## Repeatable Scripts

Download and verify:

```bash
cd /Users/kota/TrustNest/dream-work-reality
apps/ios/scripts/download-qwen-gguf-model.sh
```

Install into the booted simulator app sandbox:

```bash
cd /Users/kota/TrustNest/dream-work-reality
apps/ios/scripts/install-gguf-model-to-booted-simulator.sh
```

The install script expects the app to be installed in the booted simulator with bundle ID:

```text
com.dream.nestledger.dev
```

On this machine it installed to:

```text
~/Library/Developer/CoreSimulator/Devices/1253C9D2-75D7-4DBC-BEC6-A530DDE933B1/data/Containers/Data/Application/1C1169DD-48C3-4755-AE2E-DB789110B947/Library/Application Support/DreamWork/models/Qwen2.5-3B-Instruct-Q4_K_M.gguf
```

## Current Runtime Status

The GGUF file is now downloaded, hashed, manifest-pinned, and installed into the booted simulator sandbox.

The app/Rust pipeline now has a llama.cpp/Metal runtime path:

- `Vendor/llama.xcframework` is linked into the iOS app target.
- `apps/ios/DreamWorkApp/Sources/Native/LlamaCppBridge.mm` calls llama.cpp directly.
- `core/dreamwork_core/src/inference/llama_cpp.rs` binds Rust to that C ABI.
- `local_document_mapper.rs` applies constrained JSON fields when generation succeeds.

When llama.cpp returns usable fields, `local_document_mapper.rs` reports:

```text
gguf_metal_active
```

If generation fails or returns no usable fields, the deterministic local extraction path remains active and telemetry records the fallback reason.

## Remaining Native Runtime Work

To make the GGUF extraction production-ready:

1. Run full physical-device tests with real document scans.
2. Tune prompt/context/max-token parameters for accuracy and latency.
3. Add golden tests for valid JSON and fallback behavior once test runners can supply the GGUF artifact.
4. Benchmark memory pressure and thermal behavior on target iPhones.
