# DreamWork iOS — Publishing Guide (TestFlight & App Store)

Step-by-step instructions for building, uploading, and distributing **DreamWork** (TrustNest) to testers and the public App Store.

**Repository branch:** use **`ganga`** for release builds (latest ingest / GenAI / scan fixes).

**Current app identifiers** (from `project.yml` — update this doc if they change):

| Setting | Value |
|---------|--------|
| Bundle ID | `com.dream.nestledger.dev` |
| Marketing version | `1.0.0` |
| Build number | `14` (increment for every upload) |
| Team ID (TrustNest) | `RNBNZW828G` |

---

## Table of contents

1. [Prerequisites](#1-prerequisites)
2. [One-time Apple setup](#2-one-time-apple-setup)
3. [Prepare a release (version & code)](#3-prepare-a-release-version--code)
4. [Build the release IPA](#4-build-the-release-ipa)
5. [Verify the IPA](#5-verify-the-ipa)
6. [Upload to App Store Connect](#6-upload-to-app-store-connect)
7. [TestFlight — internal testers](#7-testflight--internal-testers)
8. [TestFlight — external testers (optional)](#8-testflight--external-testers-optional)
9. [Submit to the public App Store](#9-submit-to-the-public-app-store)
10. [Tester setup (GenAI / driver license)](#10-tester-setup-genai--driver-license)
11. [Troubleshooting](#11-troubleshooting)
12. [Quick reference commands](#12-quick-reference-commands)

---

## 1. Prerequisites

### On your Mac

- **macOS** with **Xcode** installed (use a recent stable release; match what you use for device testing).
- **Xcode command line tools:** `xcode-select --install`
- **XcodeGen:** `brew install xcodegen`
- **Rust** with iOS targets:

  ```bash
  rustup target add aarch64-apple-ios aarch64-apple-ios-sim
  ```

- **Transporter** (Mac App Store) — for uploading `.ipa` files without Xcode Organizer.
- **Git** — clone/pull `ganga` before each release.

### Apple accounts

- **Paid** [Apple Developer Program](https://developer.apple.com/programs/) membership (Personal Team / free accounts cannot upload to TestFlight for distribution at scale).
- Access to **App Store Connect** for your team.
- **Xcode → Settings → Accounts:** sign in with an Apple ID that has **Admin** or **App Manager** role on the team.

### Legal / metadata (App Store only)

- Live **Privacy Policy URL** and **Support URL** (required for App Store submission).
- Screenshots, description, age rating, and App Privacy questionnaire in App Store Connect.

---

## 2. One-time Apple setup

### 2.1 Find your Team ID

1. Open [Apple Developer → Membership](https://developer.apple.com/account).
2. Copy **Team ID** (10 characters), e.g. `RNBNZW828G`.

You will use this in archive scripts and signing.

### 2.2 Register the App ID (Bundle ID)

1. [Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list).
2. **+** → **App IDs** → **App**.
3. **Bundle ID:** `com.dream.nestledger.dev` (must match `project.yml`).
4. Enable only capabilities you use (document picker / camera do not require extra entitlements beyond defaults for current features).

If the bundle ID is unavailable, change `PRODUCT_BUNDLE_IDENTIFIER` in `apps/ios/project.yml`, run `xcodegen generate`, and register the new ID.

### 2.3 Create the app in App Store Connect

1. [App Store Connect → My Apps](https://appstoreconnect.apple.com/apps).
2. **+** → **New App**.
3. **Platform:** iOS.
4. **Name:** e.g. DreamWork or NestLedger (customer-facing name).
5. **Bundle ID:** select `com.dream.nestledger.dev`.
6. **SKU:** any unique string (e.g. `dreamwork-ios-001`).

### 2.4 Certificates & provisioning (automatic signing)

1. Open the project in Xcode once (see [§4](#4-build-the-release-ipa) — open step).
2. Target **DreamWorkApp** → **Signing & Capabilities**.
3. Enable **Automatically manage signing**.
4. **Team:** your paid team (`RNBNZW828G`).
5. **Release** should use **Apple Distribution** (Xcode creates this when you first archive).

If export fails, open **Xcode → Settings → Accounts →** your team → **Manage Certificates…** and ensure **Apple Distribution** exists.

---

## 3. Prepare a release (version & code)

### 3.1 Get the latest code

```bash
cd /path/to/dream-work-reality
git fetch origin
git checkout ganga
git pull origin ganga
```

### 3.2 Bump the build number (required every upload)

Apple rejects uploads if the **build number** was already used.

Edit `apps/ios/project.yml`:

```yaml
MARKETING_VERSION: "1.0.0"      # User-visible version (change for major releases)
CURRENT_PROJECT_VERSION: "15"   # Integer — increase by 1 each upload (was 14)
```

Regenerate the Xcode project:

```bash
cd apps/ios
xcodegen generate
```

### 3.3 Commit (recommended)

```bash
git add apps/ios/project.yml apps/ios/DreamWorkApp.xcodeproj/project.pbxproj
git commit -m "chore(ios): bump build number for TestFlight"
git push origin ganga
```

### 3.4 Pre-upload checklist

- [ ] Built from intended commit on `ganga`
- [ ] `CURRENT_PROJECT_VERSION` incremented
- [ ] `xcodegen generate` run after `project.yml` edits
- [ ] No debug-only API endpoints required for core features (Stage 2/3 use embedded Rust; Stage 1 GenAI uses Settings API key on device)

---

## 4. Build the release IPA

All commands run from **`apps/ios`** (the folder that contains `project.yml`).

```bash
cd apps/ios
```

### Option A — CLI script (recommended)

Uses **Release**, **generic iOS device**, and automatic signing:

```bash
./scripts/archive-for-testflight.sh RNBNZW828G
```

Replace `RNBNZW828G` with your Team ID if different.

**Output:** `apps/ios/build/DreamWorkApp.ipa`

The script will:

1. Run `xcodegen generate`
2. Clean `build/`
3. `xcodebuild archive` (compiles Rust for `aarch64-apple-ios` Release)
4. `xcodebuild -exportArchive` → `.ipa`

Typical duration: 2–5 minutes on Apple Silicon.

### Option B — Xcode GUI

1. `cd apps/ios && xcodegen generate && open DreamWorkApp.xcodeproj`
2. Scheme **DreamWorkApp**, destination **Any iOS Device** (not Simulator).
3. **Product → Archive**.
4. **Window → Organizer** → select archive → **Distribute App** → **App Store Connect** → **Upload**.

You can skip Transporter if upload succeeds from Organizer.

### If archive fails

| Error | Action |
|-------|--------|
| No Account for Team "YOUR_TEAM_ID" | Pass real 10-char Team ID to the script, not a placeholder |
| No profiles for … | Open project in Xcode, fix Signing, archive once from Xcode |
| Rust / linker errors | `rustup target add aarch64-apple-ios`, clean `core/target` if needed, retry |
| Signing / bundle ID conflict | Align `project.yml` bundle ID with Developer portal App ID |

---

## 5. Verify the IPA

Before upload, confirm App Store icon requirements (avoids **409** rejections):

```bash
cd apps/ios
./scripts/verify-ipa-icons.sh build/DreamWorkApp.ipa
```

Expected: `OK: IPA has AppIcon60x60@2x.png, CFBundleIconFiles, and CFBundleIconName`

Optional — confirm version inside the IPA:

```bash
TMP=$(mktemp -d)
unzip -q build/DreamWorkApp.ipa -d "$TMP"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TMP"/Payload/DreamWorkApp.app/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TMP"/Payload/DreamWorkApp.app/Info.plist
rm -rf "$TMP"
```

---

## 6. Upload to App Store Connect

### Option A — Transporter (CLI workflow)

1. Install **Transporter** from the Mac App Store if needed.
2. Open the IPA:

   ```bash
   open -a Transporter "/path/to/dream-work-reality/apps/ios/build/DreamWorkApp.ipa"
   ```

3. Sign in with the same Apple ID used in App Store Connect.
4. Click **Deliver** and wait until status is **Delivered**.

### Option B — Xcode Organizer

**Distribute App** → **App Store Connect** → **Upload** (see Option B in [§4](#4-build-the-release-ipa)).

### After upload

1. [App Store Connect](https://appstoreconnect.apple.com/) → your app → **TestFlight**.
2. New build appears with status **Processing** (often **10–30+ minutes**, sometimes longer).
3. When processing completes, the build shows a version like **1.0.0 (15)** and status **Ready to Test** or similar.

**Note:** Uploading does not email testers automatically. You must assign the build to a testing group (see below).

---

## 7. TestFlight — internal testers

Internal testing is for up to **100** users with roles in App Store Connect (team members).

### 7.1 Add testers (first time)

1. App Store Connect → **Users and Access** → invite colleagues with at least **Developer** or **Marketing** access, **or**
2. Use existing team members who already have App Store Connect access.

### 7.2 Enable the build for internal testing

1. **My Apps** → your app → **TestFlight** tab.
2. Under **Internal Testing**, select your group (or **+** create one, e.g. "DreamWork Team").
3. **+** next to **Builds** → select the new build (e.g. **1.0.0 (15)**).
4. Ensure testers are in the group.

### 7.3 Install on iPhone

Testers must:

1. Install **TestFlight** from the App Store (Apple’s blue app — **not** the App Store Connect app).
2. Sign in to TestFlight with the **same Apple ID** invited in App Store Connect.
3. Open the **email invite** from Apple or find the app inside TestFlight.
4. Tap **Install**.

### Common mistakes

| Symptom | Cause |
|---------|--------|
| Only sees **Redeem** screen | User not added to **Internal Testing** group, or no build attached to group |
| Build never appears | Still **Processing**, or upload failed in Transporter |
| Wrong app / old build | Remove old install; install latest build from TestFlight |

**There is no public “redeem code” for standard internal TestFlight** — use email invites and the TestFlight app.

---

## 8. TestFlight — external testers (optional)

For users **outside** your App Store Connect team (beta customers, QA contractors):

1. **TestFlight** → **External Testing** → create a group.
2. Add the build (first time may require **Beta App Review** by Apple — usually 24–48 hours).
3. Add testers by email or enable a **public link** (if configured).

External groups have stricter Apple review and a 10,000-tester limit.

---

## 9. Submit to the public App Store

TestFlight distribution does **not** publish the app on the App Store. For public release:

### 9.1 Complete store listing

In App Store Connect → your app → **App Store** tab:

- App description, subtitle, keywords
- Screenshots (6.7", 6.5", 5.5" etc. as required)
- **Privacy Policy URL** and **Support URL**
- **App Privacy** (data collection questionnaire)
- **Age rating**
- **Pricing**

### 9.2 Select the build

1. Create a new **version** (e.g. `1.0.0`) if needed.
2. Under **Build**, select the processed build from TestFlight.
3. Answer **export compliance** (repo sets `ITSAppUsesNonExemptEncryption` = NO unless you add non-exempt crypto).

### 9.3 Submit for review

1. **Add for Review**.
2. **Submit to App Review**.
3. Monitor **App Review** status; respond to rejection notes if any.

After approval, choose **Release** manually or automatically per your preference.

---

## 10. Tester setup (GenAI / driver license)

Builds on **`ganga`** include improved driver-license mapping. For accurate field extraction (name, address, DL #, issue/expiry):

1. Open the app → **Settings**.
2. Enter an **OpenAI API key** → **Save API key**.
3. **Home** → choose **Driver's license** → scan or import document.
4. Review fields → **Save as new person** to add under **People**.

Without an API key, the app uses on-device barcode/OCR heuristics only (less accurate on noisy scans).

**Privacy:** API keys are stored on-device for development/testing; define your production policy before App Store release.

---

## 11. Troubleshooting

### Upload / signing

| Issue | Fix |
|-------|-----|
| `No Account for Team` | Real Team ID in script; Xcode **Settings → Accounts** |
| `No profiles for com.dream.nestledger.dev` | Register App ID; automatic signing in Xcode; archive once from GUI |
| Transporter: duplicate build | Increment `CURRENT_PROJECT_VERSION` in `project.yml`, rebuild |
| Missing 120×120 icon (409) | Re-run archive; run `verify-ipa-icons.sh`; ensure post-build **actool** phase runs |

### TestFlight

| Issue | Fix |
|-------|-----|
| Processing stuck > 1 hour | Check email for Apple issues; verify compliance/export questions |
| Tester can't install | Same Apple ID as invite; Internal group has build; TestFlight app installed |
| Old behavior after install | Confirm build number in TestFlight matches latest upload |

### App functionality

| Issue | Fix |
|-------|-----|
| Wrong field mapping | Settings → OpenAI API key; use build from `ganga` ≥ build 14 |
| Person match wrong | Add existing people with DL # / DOB first; review **Person match** section |
| core-api / port 18081 | **Not required** on device for Stage 2/3 (Rust FFI). Stage 1 GenAI uses direct OpenAI from Settings |

---

## 12. Quick reference commands

```bash
# From repo root
cd apps/ios

# Regenerate Xcode project after project.yml changes
xcodegen generate

# Build release IPA (Team ID)
./scripts/archive-for-testflight.sh RNBNZW828G

# Verify icons
./scripts/verify-ipa-icons.sh build/DreamWorkApp.ipa

# Open Transporter with IPA
open -a Transporter "$(pwd)/build/DreamWorkApp.ipa"

# Run unit tests (simulator)
xcodebuild -scheme DreamWorkApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DreamWorkAppTests test
```

---

## Related files

| File | Purpose |
|------|---------|
| `project.yml` | Bundle ID, version, build number, icons |
| `scripts/archive-for-testflight.sh` | Archive + export IPA |
| `scripts/verify-ipa-icons.sh` | Pre-upload icon validation |
| `ExportOptions-ipa.plist` | Export method `app-store-connect` |
| `README.md` | Development, simulator, device install |
| `DreamWorkApp/Resources/PrivacyInfo.xcprivacy` | Privacy manifest |

---

## Release log template

Keep a short log when you ship:

| Date | Version | Build | Branch | Notes |
|------|---------|-------|--------|-------|
| 2026-05-16 | 1.0.0 | 14 | ganga | GenAI DL mapping, field validator, FFI ingest |
| | | | | |

---

*Last updated for build **14** on branch **`ganga`**. Update version table in [§3.2](#32-bump-the-build-number-required-every-upload) when shipping new builds.*
