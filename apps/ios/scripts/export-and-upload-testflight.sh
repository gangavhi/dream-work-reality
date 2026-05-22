#!/usr/bin/env bash
# Export an existing .xcarchive to .ipa and open Transporter (run on a Mac signed into Xcode).
#
# Prerequisite: archive exists (from archive-for-testflight.sh) OR archive from Xcode Organizer.
#
# Usage:
#   cd apps/ios
#   ./scripts/export-and-upload-testflight.sh RNBNZW828G
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${IOS_DIR}"

TEAM="${DEVELOPMENT_TEAM:-${1:-}}"
ARCHIVE="${IOS_DIR}/build/DreamWorkApp.xcarchive"
EXPORT="${IOS_DIR}/build/ipa-export"
PLIST_TEMPLATE="${IOS_DIR}/ExportOptions-ipa.plist"
EXPORT_PLIST="${IOS_DIR}/build/ExportOptions-export.plist"
FINAL_IPA="${IOS_DIR}/build/DreamWorkApp.ipa"

if [[ -z "${TEAM}" ]]; then
  echo "Usage: ${0} YOUR_10_CHAR_TEAM_ID" >&2
  exit 1
fi

if [[ ! -d "${ARCHIVE}" ]]; then
  echo "error: missing ${ARCHIVE}" >&2
  echo "Run ./scripts/archive-for-testflight.sh ${TEAM} first (on a Mac with Xcode → Accounts signed in)." >&2
  exit 1
fi

mkdir -p "${IOS_DIR}/build"
cp "${PLIST_TEMPLATE}" "${EXPORT_PLIST}"
if /usr/libexec/PlistBuddy -c "Print :teamID" "${EXPORT_PLIST}" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :teamID ${TEAM}" "${EXPORT_PLIST}"
else
  /usr/libexec/PlistBuddy -c "Add :teamID string ${TEAM}" "${EXPORT_PLIST}"
fi

echo "==> xcodebuild -exportArchive"
rm -rf "${EXPORT}"
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

mv -f "${IPA}" "${FINAL_IPA}"
rm -rf "${EXPORT}" "${EXPORT_PLIST}"

echo "==> verify icons"
"${SCRIPT_DIR}/verify-ipa-icons.sh" "${FINAL_IPA}"

TMP=$(mktemp -d)
unzip -q "${FINAL_IPA}" -d "${TMP}"
echo "Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${TMP}"/Payload/DreamWorkApp.app/Info.plist) ($( /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${TMP}"/Payload/DreamWorkApp.app/Info.plist))"
rm -rf "${TMP}"

echo ""
echo "IPA ready: ${FINAL_IPA}"
echo "Opening Transporter — sign in and click Deliver."
if [[ -d "/Applications/Transporter.app" ]]; then
  open -a Transporter "${FINAL_IPA}"
else
  echo "Install Transporter from the Mac App Store, then: open -a Transporter \"${FINAL_IPA}\""
fi
