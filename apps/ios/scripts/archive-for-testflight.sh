#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${IOS_DIR}"

TEAM="${DEVELOPMENT_TEAM:-${1:-K2L95UX84H}}"
ARCHIVE="${IOS_DIR}/build/TrustNest.xcarchive"
EXPORT="${IOS_DIR}/build/ipa-export"
PLIST_TEMPLATE="${IOS_DIR}/ExportOptions-ipa.plist"
EXPORT_PLIST="${IOS_DIR}/build/ExportOptions-export.plist"

echo "==> xcodegen generate"
xcodegen generate

echo "==> Clean build/"
rm -rf "${IOS_DIR}/build"
mkdir -p "${IOS_DIR}/build"

echo "==> xcodebuild archive (Release, team ${TEAM})"
xcodebuild archive \
  -project TrustNest.xcodeproj \
  -scheme TrustNest \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "${ARCHIVE}" \
  DEVELOPMENT_TEAM="${TEAM}" \
  CODE_SIGNING_ALLOWED=NO

echo "==> xcodebuild -exportArchive"
cp "${PLIST_TEMPLATE}" "${EXPORT_PLIST}"
/usr/libexec/PlistBuddy -c "Set :teamID ${TEAM}" "${EXPORT_PLIST}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :teamID string ${TEAM}" "${EXPORT_PLIST}"

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE}" \
  -exportPath "${EXPORT}" \
  -exportOptionsPlist "${EXPORT_PLIST}" \
  -allowProvisioningUpdates

IPA="$(ls "${EXPORT}"/*.ipa 2>/dev/null | head -1 || true)"
if [[ -z "${IPA}" ]]; then
  echo "error: export produced no .ipa" >&2
  exit 1
fi

FINAL_IPA="${IOS_DIR}/build/TrustNest.ipa"
mv -f "${IPA}" "${FINAL_IPA}"
echo "==> IPA ready: ${FINAL_IPA}"

if [[ "${UPLOAD_TO_TESTFLIGHT:-1}" == "1" ]]; then
  echo "==> Uploading to App Store Connect / TestFlight"
  UPLOAD_PLIST="${IOS_DIR}/build/ExportOptions-upload.plist"
  cp "${PLIST_TEMPLATE}" "${UPLOAD_PLIST}"
  /usr/libexec/PlistBuddy -c "Set :destination upload" "${UPLOAD_PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :destination string upload" "${UPLOAD_PLIST}"
  xcodebuild -exportArchive \
    -archivePath "${ARCHIVE}" \
    -exportPath "${IOS_DIR}/build/upload-export" \
    -exportOptionsPlist "${UPLOAD_PLIST}" \
    -allowProvisioningUpdates
fi

echo "Done. Check App Store Connect → TestFlight for processing status."
