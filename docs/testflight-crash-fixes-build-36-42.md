# TestFlight crash fixes — builds 36 through 42

**Marketing version:** 1.1.0  
**Deliver this build:** **42** (do not re-test 36–41 for crash behavior)  
**Branch:** `ganga-2026-05-16-2`  
**Bundle ID:** `com.dream.nestledger.dev`

---

## Executive summary

| Symptom | Root cause |
|---------|------------|
| App quits right after scan / import | iOS **jetsam** (memory kill) and/or **native llama.cpp crash** when loading ~380 MB Qwen GGUF immediately after Vision OCR |
| “Model missing” (no crash) | GGUF not in IPA or not found in bundle — separate issue, fixed in build 37+ |

**Build 42** is the intended TestFlight candidate: **scan uses OCR only on iPhone**; on-device LLM runs only when the user taps **“Extract fields on this device”**.

---

## Root cause (technical)

After a document scan, the pipeline was:

1. **Vision OCR** — allocates image/PDF memory  
2. **Automatic local LLM** — load `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf` (~380 MB) via `LlamaCppBridge.mm`  
3. Often a **second** GGUF (classifier + parser, or storage planner) on older builds  

On a physical iPhone the app has a limited memory budget. Peak usage from OCR + GGUF + llama context + (formerly) grammar sampler exceeded that budget → **jetsam** (instant quit, no in-app error).

A secondary crash vector was **llama prompt decode** with `n_batch = 32` while feeding **hundreds of prompt tokens** in one `llama_decode` call → undefined behavior / native crash inside llama.cpp (especially on device, not simulator).

---

## Chronology of fixes

### Build 36–37 — models missing vs first crash fixes

| Change | Purpose |
|--------|---------|
| Embed GGUFs in Release IPA (`project.yml` post-build script) | TestFlight installs had no models in Application Support |
| `BundledModelStore` reads `Bundle.main/Models/` | Resolve weights shipped inside the app |
| Switched from **3B → 0.5B** Qwen | 3B + full Metal offload caused jetsam on device |
| Reduced `n_gpu_layers`, `n_ctx` in `LlamaCppBridge.mm` | Lower Metal/RAM spikes |

**Commits:** `71f7f16`, `bbabea1`, `af9ae5e`

---

### Build 38 — smaller model (superseded by later builds)

Same direction as above; marketing/build bump. Superseded by 39+.

---

### Build 39 (`c0afa23`) — defer storage ML + tighter llama

| File / area | Fix |
|-------------|-----|
| `CoreBridgeService.enrichScanReview` | **`runStoragePipeline: false` by default** — no SQL planner GGUF during scan |
| `LlamaCppBridge.mm` | CPU-only (`n_gpu_layers = 0`), smaller context, `@autoreleasepool` |
| `dreamwork_llama_release_cached_model()` + `LlamaRuntime.swift` | Release weights after extraction |
| Trace | `storage:deferred:scan_review` |

**Still crashing:** automatic **classifier + parser** (two LLM passes) and storage of grammar/batch issues.

---

### Build 40 (`86b1808`) — single LLM pass + Qwen-only IPA

| File / area | Fix |
|-------------|-----|
| `DocumentIntelligenceOrchestrator.swift` | **Skip separate classifier LLM** on device; use parser `document_type` (`classify:skipped:single_pass_parser`) |
| `LlamaCppBridge.mm` | Remove grammar sampler; unload model after each call; context 512 |
| `inference/mod.rs` | Truncate OCR prompts (`DEFAULT_PROMPT_INPUT_CHARS = 1200`) |
| `project.yml` embed script | **Only** `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf` in IPA (not storage planner) |
| `CoreBridgeService` | `Task.detached` for pipeline (off main actor) |
| Token limits | Classifier 128, parser 256 max tokens |

**Still crashing:** automatic LLM still ran once per scan; `n_batch` vs long prompt; memory guard often still allowed load.

---

### Build 41 (`37eda76`) — batch decode + memory guard + OCR-first UI

| File / area | Fix |
|-------------|-----|
| `LlamaCppBridge.mm` | **`decodePromptInChunks`** — prompt fed in chunks; `n_batch = n_ctx = 512` |
| `OnDeviceMemoryGuard.swift` | Skip LLM if `os_proc_available_memory()` &lt; ~320 MB |
| `AppState.presentScanReview` | **Phase 1:** OCR-only review; **Phase 2:** auto LLM only if memory guard passes |
| `ExtractionAgent.swift` | Respect memory guard (`memory_guard` in runtime status) |

**Still crashing:** phase 2 still **auto-ran** LLM on device when memory check passed; load could still jetsam.

---

### Build 42 (`2ad1dc5`) — **definitive stability fix (deliver this)**

| File / area | Fix |
|-------------|-----|
| `OnDeviceMLPolicy.swift` | **Physical iPhone: `allowsAutomaticInferenceOnScan = false`** |
| `AppState.presentScanReview` | Opens review after **OCR only**; no automatic GGUF on iPhone |
| `AppState.runOnDeviceExtractionForCurrentScan()` | LLM only after user action |
| `ScanReviewView.swift` | Button **“Extract fields on this device”** + explanation; spinner while running |
| `CoreBridgeService` | OCR preview trace: `llm:policy:manual_trigger_required` |
| Simulator | Still auto-runs LLM for dev/tests (`#if targetEnvironment(simulator)`) |

---

## Current behavior (build 42)

### iPhone (TestFlight / Release)

```text
Scan / import
  → Vision OCR
  → Review screen (text visible, fields empty or manual)
  → User taps "Extract fields on this device" (optional)
  → Single Qwen pass (if memory guard OK)
  → Fields populate or mapping notice shown
```

### Simulator

Automatic extraction after scan still runs (policy allows it).

### Pipeline trace strings to expect

| Trace | Meaning |
|-------|---------|
| `llm:phase:ocr_preview` | Review shown without LLM |
| `llm:policy:manual_trigger_required` | iPhone waiting for user tap |
| `classify:skipped:single_pass_parser` | No separate classifier GGUF call |
| `storage:deferred:scan_review` | Storage planner not run on scan |
| `llm:skipped:available_memory_low` | Memory guard blocked load |
| `llm_document_parser_failed:memory_guard:...` | Extraction skipped (low memory) |

---

## Files touched (build 36–42 cumulative)

| Path | Role |
|------|------|
| `apps/ios/project.yml` | Embed Qwen-only; `CURRENT_PROJECT_VERSION: "42"` |
| `apps/ios/DreamWorkApp/Sources/Native/LlamaCppBridge.mm` | llama.cpp inference, memory-safe decode |
| `apps/ios/DreamWorkApp/Sources/Native/LlamaRuntime.swift` | Release cached GGUF |
| `apps/ios/DreamWorkApp/Sources/Native/OnDeviceMemoryGuard.swift` | `os_proc_available_memory` gate |
| `apps/ios/DreamWorkApp/Sources/Native/OnDeviceMLPolicy.swift` | No auto-LLM on device |
| `apps/ios/DreamWorkApp/Sources/Core/CoreBridgeService.swift` | Deferred storage; OCR vs LLM phases |
| `apps/ios/DreamWorkApp/Sources/Core/AppState.swift` | Two-phase scan review + manual extract |
| `apps/ios/DreamWorkApp/Sources/Features/Scan/ScanReviewView.swift` | Extract button UI |
| `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/DocumentIntelligenceOrchestrator.swift` | Single-pass classify |
| `apps/ios/DreamWorkApp/Sources/Intelligence/Agents/ExtractionAgent.swift` | Memory guard |
| `apps/ios/DreamWorkApp/Sources/Core/BundledModelStore.swift` | Bundle + Application Support lookup |
| `core/dreamwork_core/src/inference/mod.rs` | Prompt truncation |
| `core/dreamwork_core/src/ml_document_classifier.rs` | Lower max tokens |
| `core/dreamwork_core/src/local_document_mapper.rs` | Lower max tokens |
| `core/dreamwork_core/src/storage_routing.rs` | Storage planner (not on scan path) |

---

## IPA contents (build 42)

| Asset | In Release IPA? |
|-------|-----------------|
| `Models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf` | Yes (~380 MB) |
| `Models/SS-350M-SQL-Strict.Q8_0.gguf` | **No** (deferred; sideload for storage planner dev) |

---

## Pre-delivery checklist

- [ ] Archive with build **42** (not 40/41)
- [ ] Verify IPA: `unzip -l DreamWorkApp.ipa | grep Models/` → only Qwen GGUF
- [ ] Verify version: `CFBundleVersion` = **42**
- [ ] On device: scan → **review opens without crash**
- [ ] Tap **Extract fields on this device** → extraction runs or shows memory/notice (no quit)
- [ ] Optional: Xcode device crash log — if crash persists **before** review, capture log (likely OCR/PDF, not LLM)

---

## Build and deliver (when approved)

```bash
cd apps/ios
./scripts/archive-for-testflight.sh RNBNZW828G
./scripts/verify-ipa-icons.sh build/DreamWorkApp.ipa
# Confirm CFBundleVersion 42 in Payload/.../Info.plist
open -a Transporter build/DreamWorkApp.ipa
```

Then App Store Connect → TestFlight → wait for processing → install build **42**.

---

## Known limitations after build 42

1. **On iPhone, AI is opt-in** — not automatic after every scan (stability tradeoff).  
2. **Storage planner ML** — not run during scan; save path uses profile fields, not full ML storage apply on scan.  
3. **LayoutLMv3** — still `layout.model_missing` unless CoreML artifact ships.  
4. **Manual extract** can still fail or jetsam on very low memory — user can enter fields manually.  
5. **Crash log** — if crash happens **before** review screen, report separately (non-LLM path).

---

## Git commits (crash fix series)

```text
c0afa23  Build 39 — defer storage ML, tighter llama, release model
86b1808  Build 40 — single LLM pass, Qwen-only IPA, no grammar
37eda76  Build 41 — chunked prompt decode, memory guard, OCR-first
2ad1dc5  Build 42 — no auto-LLM on iPhone; manual extract button
```

Prior related: `bbabea1` (0.5B model), `71f7f16` (bundle models for TestFlight).

---

## Related docs

- [local-ml-only-pipeline-implementation.md](./local-ml-only-pipeline-implementation.md) — ML-only pipeline design  
- [current-state-gguf-layout-schema-telemetry.md](./current-state-gguf-layout-schema-telemetry.md) — GGUF / llama integration
