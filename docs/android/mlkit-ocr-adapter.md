# ML Kit OCR adapter (Android)

ADR **0004** requires a normalized [`NormalizedDocument`](../../core/dreamwork_core/src/ocr/mod.rs) (`pages` → `blocks` with `text`, `confidence`, `bounds` in **normalized** coordinates).

## Recommended wiring

1. Use **ML Kit Text Recognition** Latin script mode for English (`en`) documents (ADR **0018**).
2. Run recognition on the bitmap / `InputImage`.
3. Map each `Text.TextBlock` / line into `TextBlock`:
   - **`text`**: recognized string.
   - **`confidence`**: ML Kit does not expose per-character confidence uniformly—use block-level scoring where available, otherwise `1.0` and record engine metadata honestly in future provenance fields.
   - **`bounds`**: convert pixel bounding boxes to **normalized** `[0,1]` coordinates with origin **top-left** of the page (match [`VisionOcrAdapter`](../../apps/ios/DreamWorkApp/Sources/Core/VisionOcrAdapter.swift) conventions).
4. Serialize with Kotlin **`kotlinx.serialization`** JSON using the same field names as Rust `serde` (`pages`, `blocks`, `text`, `confidence`, `bounds`, `x`, `y`, `width`, `height`).
5. Pass the UTF-8 JSON string across JNI / UniFFI:
   - **`dreamwork_uniffi::dw_ocr_apply_normalized_json`**, or
   - a thin JNI entry calling the existing C ABI **`dreamwork_ocr_apply_normalized_json`** once the Kotlin string is copied to a `CString`.

## Tests

Add JVM instrumentation tests that feed a synthetic bitmap with known text and assert `dreamwork_ocr_last_document_json` / UniFFI round-trip contains expected substring counts.
