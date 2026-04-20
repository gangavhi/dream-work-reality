# ADR 0015: Native mobile UI (Swift UI / Jetpack Compose), not Flutter, for v1

## Status

Accepted

## Date

2026-04-19

## Context

The product needs **first-class** access to **camera**, **photo picker**, **BLE**, **background execution** constraints, **per-app permissions**, and eventually **system autofill / credential provider** adjacency on Android and **extension-like** companion patterns. UI can be built with:

- **Flutter** (Dart UI + platform channels to native code),
- **Kotlin Multiplatform Mobile** with Compose/SwiftUI,
- Or **fully native** UIs on each platform calling the shared **Rust** core via FFI (ADR 0013).

Flutter accelerates **one codebase** for screens but adds a **composition layer** for every platform API and can lag **cutting-edge** OS behaviors; OCR, BLE, and security-sensitive flows often accumulate **platform code** anyway.

## Decision

For **v1 mobile**, ship **native UI**:

- **iOS**: **Swift** + **SwiftUI** (UIKit where justified).
- **Android**: **Kotlin** + **Jetpack Compose**.

Both call into the **Rust** shared core (ADR 0013) for DB, crypto, ingestion orchestration, and model runtime—not a second parallel implementation in Dart.

**Flutter** is **out of scope for v1** mobile. Revisit only if product and team constraints change (e.g. dedicated Flutter team, proven FFI maturity for all required SDKs); any future adoption requires a **new ADR** superseding this one.

**Desktop** companion (extension host) may use **native** (Swift/AppKit, Tauri with Rust, or similar); that choice is **not** locked by this ADR beyond “thin shell around the same Rust core.”

## Consequences

**Positive**

- Straightforward use of **CameraX**, **AVFoundation**, **Core Bluetooth**, **Health-adjacent** patterns, and store guidelines for sensitive capabilities.
- Fewer moving parts than Flutter engine + Rust + platform plugins for hot-path features.

**Negative**

- **Two UI codebases** to maintain (Swift + Kotlin); design system discipline needed for parity.
- Slower **shared UI** iteration than a single Dart tree—accepted tradeoff for v1 quality and integration depth.

**Follow-ups**

- Shared **design tokens** (spacing, typography, colors) as data or generated constants consumed by both platforms.
