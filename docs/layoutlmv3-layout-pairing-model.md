# Layout Pairing Model: LayoutLMv3 FUNSD

## Selected Hugging Face Model

Selected model: `HYPJUDY/layoutlmv3-base-finetuned-funsd`

Source: https://huggingface.co/HYPJUDY/layoutlmv3-base-finetuned-funsd

Why this model:

- It is based on `microsoft/layoutlmv3-base`, a document AI model designed for text + bounding-box + image layout understanding.
- It is fine-tuned on FUNSD-style form understanding, which is closer to label/value extraction than plain document classification.
- It predicts form entities from OCR tokens and coordinates, which is the right input shape for the app's `VisionOcrAdapter.NormalizedDocument`.
- It keeps the architecture zero-egress once converted and bundled as CoreML.

## Current Product Rule

Heuristic spatial label/value pairing is disabled as an extraction source.

The app should not synthesize `label | value` pairs from geometry rules and pass them to `OpenVocabularyFieldExtractor` as if they were model output. If the LayoutLMv3 CoreML artifact is missing, `LayoutIntelligenceAgent` returns no label/value pairs and reports:

```text
layout.model_missing
```

If a `layoutlmv3.mlmodelc` artifact is installed and the adapter runs successfully, the engine reports:

```text
layoutlmv3.v1:active
```

Adapter failures are explicit, for example:

```text
layoutlmv3.v1:failed:unsupported_output_contract
```

This makes the state visible without silently falling back to heuristics.

## Incorporation Path

1. Convert `HYPJUDY/layoutlmv3-base-finetuned-funsd` to CoreML as `layoutlmv3.mlmodelc`.
2. Install `layoutlmv3.mlmodelc` under Application Support:

   ```text
   ~/Library/Application Support/DreamWork/models/layoutlmv3.mlmodelc
   ```

3. `ModelArtifactRegistry` discovers the artifact via `BundledModelStore.artifactPath(artifactID:)`.
4. `LayoutLMv3CoreMLAdapter` loads the model and supports two output contracts:
   - Preferred: string output containing JSON `{ "pairs": [{ "label": "...", "value": "..." }] }`.
   - Token role logits: `logits`, `role_logits`, `token_logits`, or `layout_logits` where class `1 = label`, class `2 = value`.
5. `LayoutIntelligenceAgent` feeds only model-produced pairs into the document pipeline.
6. Keep telemetry explicit:
   - `layout.model_missing`
   - `layoutlmv3.v1:active`
   - `layoutlmv3.v1:no_pairs`
   - `layoutlmv3.v1:failed:<reason>`

## Conversion Script

The repo includes:

```text
apps/ios/scripts/convert-layoutlmv3-to-coreml.sh
```

It downloads `HYPJUDY/layoutlmv3-base-finetuned-funsd`, converts a token-classification wrapper with `coremltools`, compiles it with `xcrun coremlcompiler`, and installs:

```text
~/Library/Application Support/DreamWork/models/layoutlmv3.mlmodelc
```

## Manifest Entry

The model source is tracked in `apps/ios/DreamWorkApp/Resources/model-manifest.json` as:

```json
{
  "artifact_id": "layoutlmv3.v1",
  "filename": "layoutlmv3.mlmodelc",
  "description": "HYPJUDY/layoutlmv3-base-finetuned-funsd — model-based document layout/form understanding after CoreML conversion",
  "download_url": "https://huggingface.co/HYPJUDY/layoutlmv3-base-finetuned-funsd"
}
```

## Important Limitation

The Hugging Face artifact is not an iOS-ready `.mlmodelc` file. The conversion must be validated on the target Xcode/CoreML toolchain, and model output labels may need calibration against the final converted class order. The current code intentionally avoids heuristic pairing if the model is missing or the adapter contract fails.

## Latest Conversion Attempt

The first local conversion attempt did not produce `layoutlmv3.mlmodelc`.

Observed failure:

```text
NotImplementedError: PyTorch convert function for op 'new_ones' not implemented.
```

This came from direct `coremltools` conversion of the traced LayoutLMv3 graph. The script now fails earlier on unsupported Python versions and pins a CoreML-tested dependency set, but the model may still require an export wrapper that removes dynamic attention-mask creation, or an ONNX-to-CoreML path with static masks.

Current app behavior remains correct: if `layoutlmv3.mlmodelc` is absent, `LayoutIntelligenceAgent` reports `layout.model_missing` and does not use heuristic layout pairing.
