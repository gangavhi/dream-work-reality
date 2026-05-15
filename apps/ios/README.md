# iOS app (SwiftUI + XcodeGen + Rust core)

Reproducible Xcode project from `project.yml`. The Rust static library is built per destination (simulator vs device) and per configuration (Debug vs Release) via `DreamWorkApp/Scripts/build_rust_core.sh`.

## Prerequisites

- Xcode 15+ (recommend latest stable for App Store uploads)
- Rust (`rustup`) with targets:
  - `aarch64-apple-ios-sim` (Apple Silicon simulator)
  - `x86_64-apple-ios` (Intel simulator, optional)
  - `aarch64-apple-ios` (device / App Store archives)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
rustup target add aarch64-apple-ios-sim aarch64-apple-ios x86_64-apple-ios
```

## Generate the Xcode project

After editing `project.yml` or adding Swift sources under `DreamWorkApp/Sources`:

```bash
cd apps/ios
xcodegen generate
```

## Production data store

On first use of `RustCoreBridgeService`, the app configures SQLite at:

`Application Support/DreamWork/library.sqlite`

via `dreamwork_repository_configure_persistent_sqlite` so manual entries and OCR extraction runs survive restarts.

## Run on your physical iPhone (install + OCR testing)

Use Xcode on your Mac; this repo cannot enroll your device or create signing identities for you.

### One-time setup

1. **Cable & trust** — Unlock the iPhone, connect USB (or use Xcode **Window → Devices and Simulators** after Wi‑Fi pairing). Tap **Trust This Computer** if prompted.
2. **Apple Developer** — In Xcode: **Settings → Accounts**, sign in with your Apple ID. Any **Team** works for local installs (**Personal Team** = free; apps resign after ~7 days unless you use a paid program).
3. **Developer Mode (iOS 16+)** — On the phone: **Settings → Privacy & Security → Developer Mode** → enable and reboot if Xcode asks.
4. **Rust device target** — On your Mac:

   ```bash
   rustup target add aarch64-apple-ios
   ```

5. **Generate and open the project**

   ```bash
   cd apps/ios
   xcodegen generate
   open DreamWorkApp.xcodeproj
   ```

### Signing the app

1. In Xcode, select the **DreamWorkApp** target → **Signing & Capabilities**.
2. Enable **Automatically manage signing**.
3. Choose your **Team**.
4. If Xcode reports a bundle-ID conflict, change **`PRODUCT_BUNDLE_IDENTIFIER`** in `project.yml` (e.g. `com.yourname.dreamwork.dev`), run `xcodegen generate`, then reopen.

### Build & install

1. In the toolbar, set the run destination to **your iPhone** (not a simulator).
2. **Product → Run** (⌘R).  
   The **Build Rust Core (iOS)** phase compiles `dreamwork_core` for **`aarch64-apple-ios`** (Debug uses `…/debug`, Release uses `…/release` — matches `RustCore.xcconfig`).
3. **First launch on device** — If iOS blocks the app: **Settings → General → VPN & Device Management** → trust your developer app under **Developer App**.

### Test OCR on the phone

1. Open **DreamWork** on the iPhone.
2. On **Home**, tap **Upload document (PDF or image)**.
3. Pick a file from **Files**, **iCloud Drive**, or **On My iPhone** (your driver-license JPEG or any PDF/photo with text).
4. Wait for the alert summarizing pages/regions; confirm **OCR extraction runs (SQLite)** increased on Home (each successful import appends one `extraction_run` row).

Optional: **AirDrop** the image to the phone, save to **Files**, then import from **Upload document**.

### CLI alternative (advanced)

With your phone connected and trusted:

```bash
cd apps/ios
xcodegen generate
xcrun xctrace list devices    # note your iPhone’s UDID / name
xcodebuild -project DreamWorkApp.xcodeproj \
  -scheme DreamWorkApp \
  -destination 'platform=iOS,name=YOUR_IPHONE_NAME' \
  -derivedDataPath ./DerivedDevice \
  build
```

Then install/run via Xcode’s **Devices** window or stick to **⌘R** in Xcode for the simplest loop.

## TestFlight (install on a real iPhone)

TestFlight is how you distribute **beta builds** from App Store Connect to your device (including camera / document flows). It is **not** the public App Store listing until you submit a version for review.

**Prerequisites**

1. **Paid** [Apple Developer Program](https://developer.apple.com/programs/) membership.
2. In [App Store Connect](https://appstoreconnect.apple.com/) → **My Apps**, an app whose **Bundle ID** matches `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` (see that file for the current value).
3. On your Mac: Xcode signed in (**Xcode → Settings → Accounts**) with a user on that team.
4. Rust device target: `rustup target add aarch64-apple-ios`.

**Upload a build**

- **Xcode (typical):** `xcodegen generate` → open `DreamWorkApp.xcodeproj` → **Signing & Capabilities** → select your **Team** → destination **Any iOS Device** → **Product → Archive** → **Organizer** → **Distribute App** → **App Store Connect** → **Upload**.
- **CLI + Transporter:** from `apps/ios`, run `./scripts/archive-for-testflight.sh YOUR_TEAM_ID` (Team ID: [Membership](https://developer.apple.com/account) page). Then open **Transporter** (Mac App Store), sign in, and deliver `build/ipa-export/DreamWorkApp.ipa`.

**Install on your iPhone**

1. Wait for the build to finish **Processing** in App Store Connect → **TestFlight**.
2. **TestFlight** tab → **Internal Testing** (up to 100 App Store Connect users) → create a group, add the build, add testers.
3. On the iPhone: install **TestFlight** from the App Store → accept the email invite (or open the public link if you use external testing) → install your app.

**If `exportArchive` fails with “No profiles for … were found”**

The exported `.ipa` needs an **App Store** distribution profile. With **Automatically manage signing**, archive using **Release** and a **generic iOS device** destination (the script does this). Ensure an **Apple Distribution** certificate exists (**Xcode → Settings → Accounts →** your team → **Manage Certificates…**) and that your **App ID** is registered. If export still fails, use **Xcode → Product → Archive** then **Organizer → Distribute App** once so Xcode refreshes provisioning, then try the script again.

For **internal** testers, each person must be invited in **Users and Access** in App Store Connect (or already be on the team). The first **external** TestFlight group may require a short **Beta App Review**.

## Publish to the App Store (step-by-step)

This repo cannot log into your Apple ID or press “Submit” for you. Follow these steps on **your Mac** with **Xcode that matches your shipping OS** (same major generation as device/SDK you archive against).

### A. Apple Developer Program & identifiers

1. Enroll in the **[Apple Developer Program](https://developer.apple.com/programs/)** (paid). Personal Team is **not** enough for App Store distribution.
2. In **[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)**:
   - Create an **App ID** whose **Bundle ID** matches `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` (check that file—e.g. **`com.dream.nestledger.dev`**).  
     If that ID is taken globally or by another team, change it in `project.yml`, run `xcodegen generate`, and register the **new** App ID.
   - Enable only capabilities you actually use (none required for current OCR + SQLite + document picker).

### B. App Store Connect app record

1. Open **[App Store Connect](https://appstoreconnect.apple.com/) → My Apps → + → New App**.
2. Set **Platforms** (iOS), **Name**, **Primary language**, **Bundle ID** (pick the identifier from step A), **SKU** (any unique string you choose).
3. Later you will fill **description**, **keywords**, **support URL**, **privacy policy URL**, **screenshots**, **age rating**, and **App Privacy** (nutrition labels). URLs must be live and accurate.

### C. Xcode — signing & versioning

1. `cd apps/ios && xcodegen generate && open DreamWorkApp.xcodeproj`
2. Target **DreamWorkApp → Signing & Capabilities**: **Automatically manage signing**, Team = **your paid team**, Release uses **Apple Distribution**.
3. Bump ship numbers in `project.yml` when you submit updates:
   - **`MARKETING_VERSION`** — user-facing version (e.g. `1.0.0`).
   - **`CURRENT_PROJECT_VERSION`** — build number (monotonic integer per upload, e.g. `2`, `3`, …).
   Then run `xcodegen generate` again.

### D. Archive (Release → device slice)

1. Scheme **DreamWorkApp**, destination **Any iOS Device** (or **Generic iOS Device**), **not** a simulator.
2. **Product → Archive**. Wait for completion.
3. **Release Rust note:** the Run Script runs `cargo … --release` for Release; `RustCore.xcconfig` links `aarch64-apple-ios/release`.

### E. Upload build

1. **Window → Organizer** → select the archive → **Distribute App**.
2. Choose **App Store Connect** → **Upload** (defaults usually OK: strip bitcode off for current Xcode, include symbols if offered).
3. When upload finishes, App Store Connect shows **Processing** (often 10–30+ minutes).

### F. Complete the submission in App Store Connect

1. Open your app → **TestFlight** (optional smoke test on devices) then **App Store** tab.
2. Select the **build**, attach **screenshots** (required sizes per device class), **privacy** answers, **export compliance** (aligns with `ITSAppUsesNonExemptEncryption`).
3. **Add for Review** → **Submit to App Review**.

### Repo checklist (technical)

| Item | Status in repo |
|------|----------------|
| Privacy manifest | `DreamWorkApp/Resources/PrivacyInfo.xcprivacy` |
| App Icon | `BundleAppIcons/` PNGs (incl. **120×120** `AppIcon60x60@2x.png`) in **Copy Bundle Resources** + **post-build `actool`** for `Assets.car`. Before upload: `./scripts/verify-ipa-icons.sh build/ipa-export/DreamWorkApp.ipa` |
| Encryption | `ITSAppUsesNonExemptEncryption` = NO (adjust if you use non‑exempt crypto) |
| Purpose strings | Add camera/photos strings **only** when you ship those flows |
| CLI export (optional) | `scripts/archive-for-testflight.sh`, `ExportOptions-ipa.plist`, `ExportOptions-app-store.plist.example` |

### Third-party / legal

Align **Rust / SQLite / other licenses** with your legal review; keep `cargo deny` / notices current if you distribute publicly.

## Simulator tests (CLI)

```bash
cd apps/ios
xcodebuild \
  -project DreamWorkApp.xcodeproj \
  -scheme DreamWorkApp \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  test
```

CI runs simulator tests with signing disabled; local archives use your provisioning profile.
