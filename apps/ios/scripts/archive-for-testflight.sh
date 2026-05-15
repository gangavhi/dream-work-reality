#!/usr/bin/env bash
# Build a Release .ipa for App Store Connect / TestFlight.
#
# Prerequisites:
#   - Apple Developer Program (paid)
#   - App Store Connect app whose Bundle ID matches project.yml (currently com.dream.nestledger.dev)
#   - Xcode signed in: Settings → Accounts (Apple ID with access to that team)
#   - Rust iOS device target: rustup target add aarch64-apple-ios
#
# Usage:
#   cd apps/ios
#   ./scripts/archive-for-testflight.sh YOUR_10_CHAR_TEAM_ID
#   # or: DEVELOPMENT_TEAM=YOUR_10_CHAR_TEAM_ID ./scripts/archive-for-testflight.sh
#
# Team ID: https://developer.apple.com/account → Membership details → Team ID
#
# After this script succeeds:
#   1. Upload build/ipa-export/DreamWorkApp.ipa with Transporter (Mac App Store), or
#   2. Use Xcode: Window → Organizer → Archives (if you archived from Xcode instead)
#   3. App Store Connect → your app → TestFlight → wait for Processing
#   4. TestFlight → Internal Testing → add yourself → accept invite on iPhone (install TestFlight app)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${IOS_DIR}"

TEAM="${DEVELOPMENT_TEAM:-${1:-}}"
if [[ -z "${TEAM}" ]]; then
  echo "Missing Development Team ID."
  echo "Usage: DEVELOPMENT_TEAM=XXXXXXXXXX ${0}   OR   ${0} XXXXXXXXXX"
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Install XcodeGen: brew install xcodegen" >&2
  exit 1
fi

ARCHIVE="${IOS_DIR}/build/DreamWorkApp.xcarchive"
EXPORT="${IOS_DIR}/build/ipa-export"
PLIST_TEMPLATE="${IOS_DIR}/ExportOptions-ipa.plist"
EXPORT_PLIST="${IOS_DIR}/build/ExportOptions-export.plist"

echo "==> xcodegen generate"
xcodegen generate

echo "==> Clean build/"
rm -rf "${IOS_DIR}/build"
mkdir -p "${IOS_DIR}/build"

echo "==> xcodebuild archive (Release, generic/iOS, team ${TEAM})"
xcodebuild archive \
  -project DreamWorkApp.xcodeproj \
  -scheme DreamWorkApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "${ARCHIVE}" \
  DEVELOPMENT_TEAM="${TEAM}" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates

echo "==> xcodebuild -exportArchive → IPA"
cp "${PLIST_TEMPLATE}" "${EXPORT_PLIST}"
if /usr/libexec/PlistBuddy -c "Print :teamID" "${EXPORT_PLIST}" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :teamID ${TEAM}" "${EXPORT_PLIST}"
else
  /usr/libexec/PlistBuddy -c "Add :teamID string ${TEAM}" "${EXPORT_PLIST}"
fi
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE}" \
  -exportPath "${EXPORT}" \
  -exportOptionsPlist "${EXPORT_PLIST}" \
  -allowProvisioningUpdates

IPA="$(ls "${EXPORT}"/*.ipa 2>/dev/null | head -1 || true)"
echo ""
echo "Done."
if [[ -n "${IPA}" ]]; then
  echo "  IPA: ${IPA}"
else
  echo "  Export folder: ${EXPORT}"
fi
echo ""
echo "Next: Open Transporter (Mac), sign in, and deliver the .ipa."
echo "Then App Store Connect → TestFlight → Internal Testing → add testers."
