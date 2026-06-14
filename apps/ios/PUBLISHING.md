# TrustNest iOS — TestFlight Publishing

## App

- **Name:** TrustNest
- **Bundle ID:** `com.dream-team.nestledger.dev`
- **Team:** `K2L95UX84H`
- **Version:** 1.0.0 (build 2)

## Home screen

The home page shows the **TrustNest wheel**:

- Central **house** represents the household
- **Circles** around the wheel show each family member (name + relationship)
- **ADD** circle lets you add new members
- On first launch, only the **ADD** circle appears

Household data is stored locally in SQLite with `Household_ID`, `Individual_ID`, and `Relationship_Type` per the platform docs.

## Build & publish

```bash
cd apps/ios
./scripts/archive-for-testflight.sh K2L95UX84H
```

Set `UPLOAD_TO_TESTFLIGHT=0` to export the IPA without uploading.

## TestFlight after upload

1. Open [App Store Connect](https://appstoreconnect.apple.com) → your app → **TestFlight**
2. Wait for build processing (usually 5–15 minutes)
3. Add internal testers under **Internal Testing**
4. Install via the **TestFlight** app on iPhone

## Simulator development

```bash
cd apps/ios
xcodegen generate
xcodebuild -project TrustNest.xcodeproj -scheme TrustNest \
  -destination 'platform=iOS Simulator,id=7FA77B9B-6087-4E06-823D-297F4D68C395' build
```
