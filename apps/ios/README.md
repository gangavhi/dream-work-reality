# TrustNest iOS

Privacy-first household automation app per `docs/full-context.md`.

## Architecture

- **SQLite + sqlite-vec** via [GRDBVector](https://github.com/otocolobus-com/grdb-vector) SPM
- **TrustNest Wheel** home UI (house + member circles + ADD node)
- **ProfileManager** CRUD on `profiles`
- **processDocument** ingestion (Vision OCR, 768-dim embeddings, ACID transactions)
- **Hybrid search** with mandatory `household_id` + `individual_id` filters
- **Website form fill** (member-first → URL → WKWebView + evidence badges)

## Build

```bash
cd apps/ios
xcodegen generate
xcodebuild -project TrustNest.xcodeproj -scheme TrustNest \
  -destination 'platform=iOS Simulator,id=7FA77B9B-6087-4E06-823D-297F4D68C395' build
```

## Requirements

- iOS 26+ (Foundation Models framework)
- Xcode 26+
