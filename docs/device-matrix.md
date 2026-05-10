# Device matrix and on-device models (v1)

This document **freezes the v1 naming** for **model artifacts** and **device tiers** so QA, bundling, and degradation logic stay aligned with **ADR 0017** (ONNX Runtime + llama.cpp-class LLM), **ADR 0018** (flagship iPhone + Samsung reference; English OCR), and **ADR 0004** (pluggable OCR).

**Refresh rule:** Update the **reference SKUs** and **OS floor patch versions** each release train; **artifact IDs** below change only when weights or schemas change (semver / manifest).

---

## 1. OS and store floors

| Surface | Minimum (supported install) | Recommended (full feature set) |
|--------|-----------------------------|--------------------------------|
| **iOS** | **17.0** — matches current app [`IPHONEOS_DEPLOYMENT_TARGET`](../apps/ios/project.yml) | Latest shipping iOS on primary QA devices |
| **Android** | **API 26** (Oreo) — **confirm `minSdk`** when the Android app lands; raise if ML Kit / NNAPI requirements demand it | **API 28+** for more stable NNAPI + GPU paths used by ORT EPs |

Older OS versions may **install** but run **reduced tiers** (CPU-only, smaller LLM, fewer concurrent jobs).

---

## 2. RAM capability tiers (product logic)

These tiers drive **which LLM artifact** loads by default and whether **optional downloads** are offered—not hard OS APIs.

| Tier ID | Approx. RAM | Intended experience |
|---------|-------------|---------------------|
| **`ram_min`** | **4 GB** | OCR (English) + ONNX pack on CPU + **`llm.schema.lite`** only; generative quality reduced; avoid concurrent heavy jobs. |
| **`ram_std`** | **6 GB** | Same + **`llm.schema.standard`** default where backend permits (Metal / Vulkan / NNAPI or CPU with longer latency). |
| **`ram_flagship`** | **≥ 8 GB** | **`llm.schema.standard`** comfortably; optional **`llm.schema.full`** (bundle or user-approved download). Matches **ADR 0018** primary envelope. |

Tier selection is implemented by **probe** (reported RAM + thermal / benchmark hook) and **user override** if we expose “smaller model” in settings.

---

## 3. Minimum device matrix (examples)

Use **exact SKUs** from this table for **release QA sign-off**. Substitute the **current-year flagship** when Apple/Samsung refresh hardware mid-year.

### 3.1 iOS

| Role | Example SKU | Notes |
|------|-------------|------|
| **Minimum** | **iPhone SE (3rd generation)** or **iPhone 13** class | Validates **`ram_min`** / **`ram_std`** boundary on iOS 17+. |
| **Recommended** | **iPhone 15** or newer non-Pro with **6 GB** RAM | Validates **`ram_std`** on mainstream hardware. |
| **Primary QA** | **iPhone 17 Pro** or **iPhone 17 Pro Max** | Default perf profiling, thermal budgets, ANE/Core ML EP behavior (**ADR 0018**). |

### 3.2 Android

| Role | Example SKU | Notes |
|------|-------------|------|
| **Minimum** | **6 GB RAM**, API **26–27** representative handset | Validates degraded paths; confirm **`minSdk`** before locking. |
| **Recommended** | **Pixel 8** class, API **34+** | Stock NNAPI / GLES behavior. |
| **Primary QA** | **Samsung Galaxy S26 Ultra** (or **current Galaxy S Ultra** at GA) | Samsung flagship envelope (**ADR 0018**); Vulkan/OpenCL path coverage. |

### 3.3 Desktop / simulator (engineering only)

| Role | Example | Notes |
|------|---------|------|
| **CI / dev** | macOS + **iOS Simulator** (Apple Silicon) | CPU-oriented ORT golden tests; not a substitute for device NNAPI/Thermal QA. |
| **Extension host** | macOS / Windows per extension ADRs | Inference optional; matrix focuses on **mobile** v1. |

---

## 4. Finalized model artifacts (v1)

All artifacts are **versioned** in a manifest (checksum, byte size, compatible core semver). **No remote inference** for execution—bundled or **signed optional download** only (**ADR 0001**, **ADR 0017**).

### 4.1 OCR (English-only)

| Component | Role | v1 choice |
|-----------|------|-----------|
| **Engine** | Text + geometry → normalized `OcrEngine` output (**ADR 0004**) | **Platform default:** Apple **Vision** (`VNRecognizeTextRequest`, English); Android **ML Kit Text Recognition** (Latin / English). |
| **Locale** | OCR language tag | **`en`** only (**ADR 0018**). |
| **Identifiers** | Provenance | `extraction_run.engine_id`: `vision.en.v1` · `mlkit_latin.en.v1` (examples—finalize enum in core). |

Alternate engines (Tesseract, ONNX OCR, etc.) remain **behind `OcrEngine`** for parity tests only until promoted.

### 4.2 ONNX Runtime pack (traditional ML)

| Artifact ID | Purpose | Typical EP |
|-------------|---------|------------|
| **`ort.embed.v1`** | Short-text / field similarity embeddings | Core ML / NNAPI / CPU |
| **`ort.field_type.v1`** | Field-type or block classifier | Core ML / NNAPI / CPU |
| **`ort.layout_hint.v1`** | Optional layout assists (tables, reading order) | Same |

Ship **one combined bundle** (e.g. `dreamwork_ort_pack_v1`) in CI/manifest if it simplifies signing; logical IDs above remain stable for provenance.

### 4.3 Generative LLM (schema / mapping JSON)

**Backend binding:** **llama.cpp–class** with **Metal** (iOS/macOS), **Vulkan** preferred on Android flagship (**ADR 0017**), **CPU** fallback with **`lite`** tier.

**Implementation split:** `dreamwork_core` ships **GGUF header inspection** (`parse_gguf_header_prefix`) for pins and QA; **mmap + decode + inference** stays in **platform llama.cpp-class binaries** wired through **`GenerativeLlmSession`**—avoid duplicating llama.cpp inside portable Rust CI builds.

#### 4.3.1 License constraint (v1 default)

| Constraint | What we require |
|------------|-----------------|
| **Weight license** | **Apache-2.0** for the **base instruct checkpoint**, so shipping quantized derivatives inside or beside the app is **predictable** for commercial products (patent grant, redistribution, NOTICE requirements are well understood). |
| **Build / runtime** | **llama.cpp** and **GGUF** are MIT-licensed stacks we link or vendor per our build policy—**separate** from weight license; keep SBOM entries for both. |
| **Gated hubs** | Some Hugging Face repos require **account + license acceptance** before download; CI and release pipelines must use **authenticated** pulls or **internally mirrored** blobs so builds are reproducible. |

**Re-verify** the SPDX tag on the **exact** revision before each store submission; upstream README/license files override this document if they diverge.

#### 4.3.2 Pinned base models and GGUF filenames (single family across tiers)

We standardize on **Qwen2.5 Instruct** (`Qwen/Qwen2.5-*-B-Instruct`) as the **English-first instruct** line: strong JSON/tool-style adherence at small sizes, one **chat template** and tokenizer story across tiers, and **Apache-2.0** on the base checkpoints as published on Hugging Face.

**GGUF builds** below reference community conversions maintained by **`bartowski`** (multiple quantization blobs per repo). **Pin by SHA-256** of the downloaded file in the shipping manifest—not only by filename—because HF file blobs can be replaced.

| Tier artifact ID | Upstream base (HF) | GGUF repo (HF) | **Pinned filename** (v1 default) |
|------------------|-------------------|----------------|----------------------------------|
| **`llm.schema.lite.v1`** | [`Qwen/Qwen2.5-3B-Instruct`](https://huggingface.co/Qwen/Qwen2.5-3B-Instruct) | [`bartowski/Qwen2.5-3B-Instruct-GGUF`](https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF) | `Qwen2.5-3B-Instruct-Q4_K_M.gguf` |
| **`llm.schema.standard.v1`** | [`Qwen/Qwen2.5-7B-Instruct`](https://huggingface.co/Qwen/Qwen2.5-7B-Instruct) | [`bartowski/Qwen2.5-7B-Instruct-GGUF`](https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF) | `Qwen2.5-7B-Instruct-Q4_K_M.gguf` |
| **`llm.schema.full.v1`** | Same **7B** base | Same GGUF repo | `Qwen2.5-7B-Instruct-Q5_K_M.gguf` |

**Rationale (why this stack)**

- **One lineage:** Lite ↔ standard ↔ full differ mainly by **parameters** and **quant**, reducing tokenizer drift and evaluator duplication versus mixing unrelated families per tier.
- **Latency vs quality:** **3B Q4_K_M** targets **`ram_min`** thermals; **7B Q4_K_M** is the **`ram_std` / flagship** default balance; **7B Q5_K_M** improves JSON fidelity where VRAM/RAM headroom exists (**ADR 0017** tiers).
- **Task fit:** Instruct-tuned **Qwen2.5** has been widely reported (and internally should be golden-tested) to follow **structured output** and tool-style prompts—aligned with **ADR 0005** constrained JSON plans.
- **OSS provenance:** Base weights carry **Apache-2.0**; GGUF repos typically inherit downstream obligations—still run **legalNotice** strings and **NOTICE** files in the app.

**Alternate (if product mandates non–Apache weights later):** e.g. **Llama 3.x** (Llama Community License) or **Phi-3** (**MIT** weights)—switching is an **upgrade/switch** cycle below, not a silent filename swap.

#### 4.3.3 Switching models or upgrading to a newer version

Use this process whenever **any** of these change: base model family, GGUF quant, **`llama.cpp` / GGUF ABI**, or prompt/schema DSL version tied to a model generation.

1. **Legal / licensing gate** — Confirm SPDX + redistribution terms for **new** weights; update in-app **OSS disclosures** and **NOTICE**; if the hub is gated, register compliance (HF org acceptance, export classification if applicable).
2. **Technical pin** — Download candidate GGUF(s); compute **SHA-256**; record **manifest fields**: `artifact_id`, `logical_version` (e.g. `llm.schema.standard.v2`), `source_url`, `sha256`, `bytes`, compatible **`llama.cpp` commit or semver**, **context length**, and **chat template id** used by the Rust shim.
3. **Compatibility** — Bump **`GenerativeLlmSession`** adapter if vocab, special tokens, or grammar-backend quirks changed; run **ABI smoke tests** on **iOS Metal + Android Vulkan + CPU**.
4. **Quality regression** — Extend **golden prompts** for schema JSON (happy path, ambiguity, empty OCR snippets); compare **parse success rate** and **invalid-JSON rate** vs prior pin; widen tolerances only with reviewer sign-off.
5. **Performance / thermal** — Re-run **device-matrix QA SKUs** (Section 3); confirm **`ram_min`** still meets latency ceilings or explicitly **retire** a tier from that SKU.
6. **Provenance / UX** — Never rewrite historical **`extraction_run`** rows; new runs use **`model_version`** / **`artifact_id`** reflecting the new pin. If outputs can change materially, ship **optional “re-run structuring”** rather than silent mutation.
7. **Rollout** — Prefer **optional download** canary (feature flag / staged %) before replacing **bundled** weights; keep **prior artifact** available for rollback until telemetry stabilizes.
8. **Documentation** — Update **this file** and the **release changelog**; if assumptions cross ADRs (runtime choice, privacy posture unchanged), a short **ADR addendum** or new ADR is optional but recommended when rationale is non-trivial.

**Minor refreshed GGUF** (same base checkpoint, same quant label, rebuilt by converter): treat as **patch** only if SHA changes—still run steps **2–5** minimally (hash update + CI golden suite).

---

## 5. Related ADRs and code

- **ADR 0017** — ONNX Runtime + llama.cpp-class LLM  
- **ADR 0018** — Flagship iPhone + Samsung; English OCR v1  
- **ADR 0004** — Pluggable OCR  
- iOS deployment target: [`apps/ios/project.yml`](../apps/ios/project.yml)
