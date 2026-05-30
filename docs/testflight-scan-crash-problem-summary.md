# DreamWork iOS — Scan crash problem summary

**Last updated:** 2026-05-28  
**Affected flow:** Document scan / import → scan review  
**Recommended TestFlight build:** **42** (1.1.0)  
**Branch:** `ganga-2026-05-16-2`

---

## Problem (one paragraph)

On TestFlight, the app often **quits immediately after scanning or importing a document**, before or while showing extracted fields. This is not a normal “model missing” or validation error—the UI does not get a chance to show a friendly failure. The failure is caused by **loading and running a large on-device language model (Qwen 0.5B GGUF, ~380 MB) in the same flow as Vision OCR**, which pushes peak memory past what iOS allows on a physical iPhone. The system kills the process (**jetsam**). In some builds, a **native llama.cpp bug** (decoding a long prompt with too small a batch size) also caused crashes.

---

## Symptoms

| What users see | What it usually is |
|----------------|-------------------|
| App disappears right after scan | iOS **jetsam** (out-of-memory kill) |
| App disappears a second after review opens | Automatic LLM still running in background (builds 40–41) |
| App stays open; empty fields + orange notice | **Not a crash** — model missing or ML failed safely |
| Works in Simulator, fails on iPhone | Simulator has more memory; policy differs in build 42 |

---

## Root cause

### Primary: memory (jetsam)

```text
User scans document
    → Vision OCR (image/PDF in memory)
    → Load Qwen GGUF (~380 MB) + llama context + decode buffers
    → Peak RAM > iOS limit for the app
    → iOS terminates the app (no Swift catch)
```

Contributing factors on older builds:

- **Two LLM inferences per scan** (separate classifier + field parser, same GGUF).
- **Third model** on scan path (storage planner ~362 MB) in builds before 39.
- **Bundled 3B Qwen** (~1.9 GB) in early TestFlight IPAs.
- **Grammar-constrained sampling** in llama (extra large allocations).
- **Two GGUF files** embedded in IPA (~760 MB) increasing pressure.

### Secondary: native llama.cpp

- Prompts after OCR are often **hundreds of tokens**.
- Build 40 used `n_batch = 32` while passing the **full prompt** to `llama_decode` in one call → risk of **native crash** on device.

### Not the main crash cause

- Missing LayoutLM / “model missing” in pipeline trace → fail-closed, app continues.
- Storage planner deferred → avoids extra GGUF on scan (build 39+).
- Save button path → does not auto-run LLM today.

---

## What we tried (builds 36–41)

| Build | Approach | Result |
|-------|----------|--------|
| 36–37 | Embed models in IPA; 0.5B instead of 3B | Fixed “model missing”; crashes continued on scan |
| 39 | Defer storage ML; release GGUF; smaller llama context | Reduced load; crashes continued |
| 40 | Single LLM pass; Qwen-only IPA; no grammar sampler | Reduced load; crashes continued |
| 41 | Chunked prompt decode; memory guard; OCR-first then auto-LLM | Crashes continued when auto-LLM still ran |

**Conclusion:** Patches could not make **automatic** post-OCR inference reliable on iPhone with the current model size.

---

## Current solution (build 42)

**Policy:** On **physical iPhone**, do **not** load the GGUF automatically after scan.

| Step | Behavior |
|------|----------|
| 1 | OCR runs; **Review scan** opens with text (no LLM) |
| 2 | User taps **“Extract fields on this device”** if they want AI |
| 3 | One Qwen pass runs (with memory guard + safe llama decode) |

**Code:** `OnDeviceMLPolicy.swift`, `AppState.presentScanReview`, `ScanReviewView` extract button.

**Simulator:** Still runs automatic extraction for development.

**Tradeoff:** Stability and ML-only extraction when requested vs. zero-tap “magic” on every scan.

---

## Technical safeguards (build 36–42, cumulative)

- Bundle only **Qwen 0.5B** in Release IPA (not storage planner).
- **CPU-only** llama (`n_gpu_layers = 0`).
- **Chunked** prompt decode; `n_batch` aligned with context.
- **Prompt truncation** in Rust (1200 chars).
- **Unload GGUF** after each inference.
- **`os_proc_available_memory`** guard before load.
- **Single parser pass** for document type (no separate classifier LLM on device).
- **Storage planner deferred** on scan review.

---

## How to verify after install

1. Install TestFlight build **42** only.
2. Scan a document → **Review scan** must open without quitting.
3. Optionally tap **Extract fields on this device** → fields fill or a notice appears (not an instant quit).
4. If crash happens **before** step 2 → capture Xcode device crash log (likely OCR/PDF, not LLM).

---

## Long-term direction (optional)

To restore **automatic** AI after scan without crashes:

- Use a **smaller** or task-specific on-device model, or
- Run inference **later** (idle / background) with strict memory budget, or
- Use lighter extraction (layout/rules) for common docs and LLM only for hard cases.

Until then, **manual extract on iPhone is the recommended production behavior.**

---

## Related documentation

- [testflight-scan-crash-problem-summary.md](./testflight-scan-crash-problem-summary.md) — problem summary
- [document-scan-crash-simulator-investigation.md](./document-scan-crash-simulator-investigation.md) — simulator reproduction, post-upload flow, measured memory timeline
- [testflight-crash-fixes-build-36-42.md](./testflight-crash-fixes-build-36-42.md) — per-build fix log
---

## Git reference (crash-fix commits)

```text
71f7f16  Bundle local ML models for TestFlight
bbabea1  Fix TestFlight crash — 0.5B Qwen
c0afa23  Build 39 — defer storage ML, tighter llama
86b1808  Build 40 — single LLM pass, Qwen-only IPA
37eda76  Build 41 — chunked decode, memory guard
2ad1dc5  Build 42 — manual extract on iPhone (recommended)
845eec0  Document crash fixes (builds 36–42)
```
