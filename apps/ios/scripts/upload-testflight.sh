#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="TrustNest"
PROJECT="TrustNest.xcodeproj"
ARCHIVE_PATH="$ROOT/build/TrustNest.xcarchive"
EXPORT_PATH="$ROOT/build/export"
EXPORT_OPTIONS="$ROOT/ExportOptions.plist"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Archiving for App Store"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=K2L95UX84H

echo "==> Exporting IPA"
rm -rf "$EXPORT_PATH"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

IPA_PATH="$(find "$EXPORT_PATH" -name '*.ipa' | head -1)"
echo "==> Uploading $IPA_PATH to TestFlight"

if [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  xcrun altool --upload-app \
    --type ios \
    --file "$IPA_PATH" \
    --apiKey "$APP_STORE_CONNECT_KEY_ID" \
    --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
else
  echo "Using Apple ID credentials from keychain (xcodebuild -exportArchive with destination upload)"
fi

echo "==> Done. Check App Store Connect for processing status."
