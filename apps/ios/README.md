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

## App Store checklist (operator steps)

Apple review is manual; this repo wires technical prerequisites only.

1. **Apple Developer Program** — enroll and create an App ID matching `PRODUCT_BUNDLE_IDENTIFIER` (default `com.dreamwork.app`; change if you ship under your team).
2. **Signing** — In Xcode: select your **Team**, enable automatic signing for Release, and archive with **Any iOS Device** / **DriverKit** destination off (generic **iOS Device**).
3. **Archive uses Release** — The Run Script builds `cargo … --release` for Release; `RustCore.xcconfig` links `core/target/aarch64-apple-ios/release`.
4. **Icons** — Replace `DreamWorkApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` with branded artwork (same single-size catalog layout is fine for modern Xcode; validate with **Archive → Validate App**).
5. **Privacy** — `PrivacyInfo.xcprivacy` declares no tracking and no collected types as shipped; update it if you add analytics, ads, or APIs that require “required reason” strings. Answer App Store Connect **Privacy Nutrition Labels** to match behavior.
6. **Purpose strings** — Add usage descriptions (e.g. `NSCameraUsageDescription`) before shipping flows that use the camera, photo library, or microphone (Vision OCR on live camera will require these).
7. **Encryption export** — `ITSAppUsesNonExemptEncryption` is set to **NO** for standard/TLS-only use; adjust if you ship custom non-exempt crypto.
8. **Support URL & privacy policy URL** — Required or expected for review; host pages that match your data practices.
9. **Third-party licenses** — Rust/SQLite and other deps: keep `cargo deny` / notices aligned with your legal review.

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
