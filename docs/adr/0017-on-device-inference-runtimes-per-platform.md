# ADR 0017: On-device inference runtimes per platform (ONNX Runtime + llama.cpp-class LLM)

## Status

Accepted

## Date

2026-04-19

## Context

ADRs **0005** (schema inference) and **0006** (form-fill intelligence) assume **on-device** models: small networks for classification/embedding, and **generative** models for structured JSON plans and ambiguous field resolution. The **Rust** core (ADR **0013**) must call into runtimes that differ by OS and hardware (**ANE**, **GPU**, **NPU**, thermal limits).

We need one **coherent strategy** so we do not ship incompatible model stacks per surface.

**Two model families** (both may coexist in one app):

1. **Small ONNX models** — embeddings, field-type classifiers, layout helpers; **ONNX** is the **portable artifact** format.
2. **Generative LLMs** — quantized weights, often shipped as **GGUF** (or vendor formats); inference via a **llama.cpp–class** engine with **Metal** / **Vulkan** / **CPU** backends, not necessarily ONNX.

## Decision

### Abstraction

- Define **Rust traits** (names illustrative): `OnnxInferenceSession` for tensor-in/tensor-out ONNX graphs, and `GenerativeLlmSession` for text-in / token-stream or text-out generation with **grammar or JSON-schema constraints** at the caller (see ADR 0005).
- **No** direct vendor SDK calls scattered across the codebase—only behind these traits + thin platform shims.

### ONNX (classifiers, embedders, small networks)

- Use **ONNX Runtime** as the **default** cross-platform engine, linked into the Rust core per target.
- **Execution providers** (pick at build or runtime when supported):
  - **iOS / macOS**: **Core ML** EP where available; fallback **CPU** (and **XNNPACK** where ORT enables it for our builds).
  - **Android**: **NNAPI** EP on devices/API levels where stable; fallback **CPU** / **XNNPACK**.
  - **Windows**: **DirectML** EP where bundled and tested; fallback **CPU**.
  - **Linux desktop**: **CPU** default; optional **CUDA** / **ROCm** EPs for companion **desktop** builds only if product needs them—**not** required for mobile.

Model artifacts remain **versioned ONNX files** checked in or downloaded from a **signed, user-approved** update channel; **no** remote inference by default (ADR 0001).

### Generative LLMs (schema / mapping JSON)

- Use a **llama.cpp–compatible** stack (e.g. **llama.cpp** via maintained Rust bindings, or **mlx**/**Metal** on Apple **only** if we commit to a second backend—avoid unless benchmarks justify the duplication).
- **Per platform backends** inside that stack:
  - **Apple (iOS/macOS)**: **Metal** GPU acceleration when available.
  - **Android**: **Vulkan** or **OpenCL** per what the chosen engine supports on target devices; **CPU** fallback with reduced model size tier.
  - **Windows/Linux desktop companion**: **CUDA** / **Vulkan** / **CPU** per build flavor; **CPU-only** remains valid for low-end PCs.

**GGUF** (or the project’s chosen quantized format) is the **shipping artifact** for generative models unless we standardize on ONNX-exported LLMs later—either way, **one** generative path per release train to limit QA matrix.

### Capability tiers

- Ship **model size tiers** (e.g. “lite” CPU-only vs “full” GPU) selected by **device RAM**, **benchmark probe**, or **user setting**—honest degradation when the device cannot run the larger model.

### Network isolation

- Inference runs **offline**; the runtime must **not** open network sockets for model execution. (Telemetry is separate and opt-in per ADR 0010.)

## Consequences

**Positive**

- Clear split: **ONNX Runtime** for traditional ML graphs; **llama.cpp-class** for generative text—each uses industry-standard tooling.
- Platform accelerators (Core ML, NNAPI, Metal) are **opt-in** at the EP/backend layer without rewriting model logic in Swift/Kotlin.

**Negative**

- **Two** inference stacks to build, sign, and security-patch (ORT + llama.cpp-class).
- **APK/IPA size** grows with bundled weights; needs **on-demand download** or **install-time** variants (product decision, not repeated here).
- **Behavioral variance** across EPs (numerics, performance) requires **golden tests** per tier.

**Follow-ups**

- CI: **deterministic** CPU-only golden tests for ONNX graphs; **non-flaky** bounds for generative outputs where possible (grammar helps).
- Document **minimum device** matrix once first models are frozen.
