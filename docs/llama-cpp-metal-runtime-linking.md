# llama.cpp / Metal Runtime Linking

## What This Means

Linking `llama.cpp`/Metal means the iOS app now carries a native GGUF inference engine in addition to the downloaded `.gguf` model file.

Before this link step, the app could:

- Find the Qwen GGUF file.
- Verify that the GGUF header was valid.
- Report `gguf_valid_runtime_unavailable`.
- Fall back to deterministic heuristic extraction.

After this link step, the app can:

- Link the upstream `llama.xcframework` into the iOS target.
- Load the native binary slices needed for iPhone and simulator builds.
- Link Apple runtime dependencies required by llama.cpp: `Metal`, `Accelerate`, `Foundation`, and the C++ runtime.
- Keep the model and inference path local to the device.

The runtime path now includes the Rust/C FFI wrapper. When a header-valid GGUF path is provided on iOS, Rust calls into an Objective-C++ shim, which calls llama.cpp to load the model, run a JSON-constrained generation prompt, and return schema JSON to `local_document_mapper.rs`. If generation fails or returns no fields, the deterministic mapper still returns a fallback result and telemetry records the reason.

## What Was Added

- `apps/ios/scripts/install-llama-xcframework.sh`
  - Downloads the pinned upstream llama.cpp XCFramework.
  - Verifies the SHA-256 checksum.
  - Installs it into `apps/ios/Vendor/llama.xcframework`.

- `apps/ios/project.yml`
  - Links `Vendor/llama.xcframework` into `DreamWorkApp`.
  - Embeds and code-signs the dynamic framework for iOS execution.

- `apps/ios/DreamWorkApp/RustCore.xcconfig`
  - Adds explicit link dependencies for `Metal`, `Accelerate`, `Foundation`, and `libc++`.

- `core/dreamwork_core/src/local_document_mapper.rs`
  - Calls `OnDeviceGenerativeSession.generate_schema_plan_json(...)` when the GGUF model is present and header-valid.
  - Applies parseable LLM fields into the mapper result.
  - Reports `gguf_metal_active` only after real llama.cpp generation returns usable fields.

- `core/dreamwork_core/src/inference/llama_cpp.rs`
  - Binds Rust to the narrow C ABI used by the app target.

- `apps/ios/DreamWorkApp/Sources/Native/LlamaCppBridge.mm`
  - Loads the GGUF model with `llama_model_load_from_file`.
  - Creates a llama context with Metal offload enabled through `n_gpu_layers`.
  - Uses llama.cpp tokenization, decode, sampler, and JSON grammar sampler APIs.
  - Returns the first balanced JSON object to Rust.

## Runtime State

Current state:

```text
GGUF model file: present and header-valid
llama.cpp framework: linked into iOS app
Metal framework: linked
Rust FFI generation wrapper: implemented
LLM-backed schema JSON: active when generation succeeds
Extraction fallback: deterministic heuristic mapper when generation fails/no-fields
```

The review UI should now distinguish successful llama.cpp output (`gguf_metal_active`) from fallback states such as `gguf_valid_llama_cpp_no_fields` or `gguf_valid_llama_cpp_generation_failed:*`.

## Why Metal Matters

`Metal` is Apple's GPU compute framework. For GGUF inference, it lets llama.cpp offload transformer operations from CPU to GPU where supported. That matters because document extraction prompts require token generation, and CPU-only generation on a phone can be slow, hot, and battery-heavy.

With Metal active, the target behavior is:

- Faster local inference.
- Lower CPU pressure.
- Better viability for TestFlight/device use.
- No document text sent to cloud services.

## Remaining Work

1. Run a full on-device validation pass using the installed Qwen GGUF model.

2. Tune prompt, context size, generation length, and schema grammar for real scans.

3. Add latency, memory-pressure, and thermal benchmarks on physical devices.

4. Add golden tests for successful generation once the test environment can reliably supply the GGUF model.

5. Consider caching context/KV state if repeated document chunks need lower latency.

## Validation

The Xcode project was regenerated, the iOS app built with the wrapper compiled/linked, and the focused iOS simulator pipeline test passed:

```text
xcodegen generate
xcodebuild test -scheme DreamWorkApp \
  -destination 'platform=iOS Simulator,id=1253C9D2-75D7-4DBC-BEC6-A530DDE933B1' \
  -only-testing:DreamWorkAppTests/DocumentIntelligencePipelineTests/testPipelineRunsClassificationTemplateExtractionThenIdentityGraph
```

