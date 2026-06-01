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
#   ./scripts/archive-for-testflight.sh ABCDE12345   # your real 10-char Team ID from developer.apple.com
#   # or: DEVELOPMENT_TEAM=ABCDE12345 ./scripts/archive-for-testflight.sh
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
if [[ "${TEAM}" == "YOUR_TEAM_ID" || "${TEAM}" == "YOUR_10_CHAR_TEAM_ID" ]]; then
  echo "error: Replace the placeholder with your real Apple Developer Team ID (10 characters)." >&2
  echo "  Example: ${0} ABCDE12345" >&2
  echo "  Find it: https://developer.apple.com/account → Membership details → Team ID" >&2
  exit 1
fi
if [[ "${#TEAM}" -ne 10 ]]; then
  echo "warning: Team ID is usually exactly 10 characters; got length ${#TEAM}: ${TEAM}" >&2
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Install XcodeGen: brew install xcodegen" >&2
  exit 1
fi

echo "==> install ONNX Runtime xcframework (App Store signable)"
chmod +x "${SCRIPT_DIR}/install-onnxruntime-xcframework.sh"
"${SCRIPT_DIR}/install-onnxruntime-xcframework.sh"

echo "==> download MiniLM ONNX field mapper"
chmod +x "${SCRIPT_DIR}/download-minilm-onnx-model.sh"
"${SCRIPT_DIR}/download-minilm-onnx-model.sh"

echo "==> install LayoutLMv3 CoreML (optional — heuristic fallback if conversion fails)"
chmod +x "${SCRIPT_DIR}/install-layoutlmv3-coreml.sh"
"${SCRIPT_DIR}/install-layoutlmv3-coreml.sh"

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
if [[ -z "${IPA}" ]]; then
  echo "error: export produced no .ipa in ${EXPORT}" >&2
  exit 1
fi

# Single canonical artifact: remove xcarchive, export logs, and duplicate paths.
FINAL_IPA="${IOS_DIR}/build/DreamWorkApp.ipa"
mv -f "${IPA}" "${FINAL_IPA}"
rm -rf "${ARCHIVE}" "${EXPORT}" "${EXPORT_PLIST}"

echo "==> verify ONNX Runtime is statically linked (not embedded)"
VERIFY_TMP="$(mktemp -d)"
unzip -q "${FINAL_IPA}" -d "${VERIFY_TMP}"
VERIFY_APP="${VERIFY_TMP}/Payload/DreamWorkApp.app"
if [[ -d "${VERIFY_APP}/Frameworks/onnxruntime.framework" ]]; then
  echo "error: onnxruntime.framework must not be embedded — it is a static library" >&2
  rm -rf "${VERIFY_TMP}"
  exit 1
fi
if ! otool -L "${VERIFY_APP}/DreamWorkApp" 2>/dev/null | grep -q onnxruntime; then
  if ! nm "${VERIFY_APP}/DreamWorkApp" 2>/dev/null | grep -q Ort; then
    echo "warning: could not confirm ORT symbols in main binary (may still be linked)" >&2
  fi
fi
codesign --verify --deep --strict --verbose=2 "${VERIFY_APP}"
rm -rf "${VERIFY_TMP}"
echo "OK: no unsigned onnxruntime.framework in bundle; app signature valid"

echo ""
echo "Done."
echo "  IPA (upload this file only): ${FINAL_IPA}"
echo ""
echo "Verify before upload:"
echo "  ${SCRIPT_DIR}/verify-ipa-icons.sh ${FINAL_IPA}"
echo ""
if [[ -d "/Applications/Transporter.app" ]]; then
  echo "Opening Transporter — sign in and click Deliver."
  open -a Transporter "${FINAL_IPA}"
else
  echo "Next: Open Transporter (Mac App Store), sign in, and deliver the .ipa above."
fi
echo "Then App Store Connect → TestFlight → Internal Testing → add testers."
