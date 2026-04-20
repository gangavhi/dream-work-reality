# ADR 0013: Rust for the shared native core (not C++)

## Status

Accepted

## Date

2026-04-19

## Context

ADR 0003 commits to a **shared native core** with a narrow FFI surface to Android, iOS, desktop, and the extension host. The implementation language must support:

- **Memory safety** by default for crypto, parsing, and DB-adjacent code (fewer exploitable bug classes than hand-rolled C++).
- **Cross-compilation** to mobile and desktop targets with a single **Cargo**-driven workflow.
- **FFI ergonomics** toward Swift and Kotlin (stable C ABI, **UniFFI**, **cxx**, or equivalent).
- **Ecosystem** for SQLite bindings, cryptography (**ring** / **aws-lc-rs**), and future ONNX / LLM bindings without locking us into a single vendor.

**C++** remains viable for teams with deep existing investment or mandatory SDKs shipped only as C++ headers—but it shifts more correctness burden to discipline and tooling.

## Decision

Implement the shared core in **Rust**.

- **C++** is **not** the default for new code in the core. Use C/C++ **only** at **thin integration boundaries** when a vendor SDK or OS API requires it (OCR vendor static libs, etc.), wrapped behind Rust modules with `unsafe` minimized and documented.
- **Build**: **Cargo** as the source of truth for the core artifact; platform shells (Gradle, Xcode, CMake for desktop host) invoke **cargo build** for the appropriate target triples.
- **FFI**: Expose a **C ABI** (or **UniFFI**-generated bindings) as the stable contract; Swift and Kotlin call into **one** compiled `libdreamworkcore` (name TBD) per platform.

## Consequences

**Positive**

- Strong defaults for memory safety and concurrency correctness in security-critical paths.
- Reproducible builds and dependency auditing via **cargo-audit** / SBOM practices (process, not automatic guarantee).
- Growing industry pattern for shared mobile + desktop libraries.

**Negative**

- Team must own **Rust toolchain** and FFI debugging (stack traces across language boundaries).
- Some third-party SDKs are C++-only: integration cost for **shim layers** or Objective-C++ bridges on Apple.
- Compile times and **ipa/apk** size need monitoring (LTO, strip, split per architecture).

**Follow-ups**

- Pin **MSRV** (minimum supported Rust version) in CI.
- Document **panic policy** across FFI boundary (must not unwind into foreign code—abort or catch at boundary).
- **ML inference stacks** (ONNX Runtime + generative engine) per platform: **ADR 0017**.
