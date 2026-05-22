# TestFlight build 29 — document intelligence (Phase A/A+)

**Version:** 1.1.0 (29)  
**Branch:** `ganga-2026-05-16-2`  
**Date:** May 21, 2026

## Why build 29 (not full Phase B LLM)

| Option | Verdict |
|--------|---------|
| **Phase A/A+** (this build) | **Shipped** — best TestFlight increment now: fixes mapping without multi‑GB model or llama.cpp integration |
| **Phase B** (bundled Qwen GGUF + Metal) | **Deferred** — no GGUF weights in repo; inference runtime is header-check only ([device-matrix.md](device-matrix.md)) |

## What testers get

1. **Default on-device mapping** — Rust heuristics + layout label\|value pairs (zero egress).
2. **PDF417 / MRZ** — barcode and passport zone fields without network.
3. **OCR grounding** — drops field values that do not appear in scan text (fewer false SSN/names on bills).
4. **Honest review UX** — mapping notices, **Estimated** vs high confidence, per-field **source** (Barcode, MRZ, On-device, Estimated).
5. **India IDs** — Aadhaar/PAN keyword + number heuristics in Rust mapper.
6. **No `PersonNameResolver`** on general ingest — Texas/passport name bleed removed.

## Settings

- **On-device (built-in, no network)** — default.
- Optional LAN Ollama / DEBUG cloud — falls back to on-device mapper if unreachable.
- Optional GGUF install path documented; full inference in a future build.

## QA focus

| Scenario | Expected |
|----------|----------|
| US DL with PDF417 | DL number, name, dates from barcode when visible |
| Passport MRZ | Name, passport number from MRZ |
| Utility bill | Fewer random SSN/name fields; “Estimated” labels |
| SSN card | SSN only when “Social Security” context present |
| Network Ollama on iPhone at 127.0.0.1 | Notice + on-device fallback |

## Docs

- [privacy-first-document-intelligence-architecture.md](privacy-first-document-intelligence-architecture.md)
- [project-requirements-and-implementation-gap.md](project-requirements-and-implementation-gap.md)
- [field-mapping-accuracy-analysis.md](field-mapping-accuracy-analysis.md)

## Build

```bash
cd apps/ios
./scripts/archive-for-testflight.sh RNBNZW828G
# Upload apps/ios/build/ipa-export/DreamWorkApp.ipa via Transporter
```
