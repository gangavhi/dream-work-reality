#!/usr/bin/env bash
# Wipe local Xcode/build caches for DreamWorkApp and regenerate a clean project.
# Does NOT delete source code, Vendor binaries, or ~/Library/Application Support/DreamWork/models.
#
# Usage:
#   cd apps/ios
#   ./scripts/reset-local-xcode-state.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${IOS_DIR}"

echo "==> Quit Xcode if it is open (best effort)"
osascript -e 'tell application "Xcode" to quit' 2>/dev/null || true
sleep 2

echo "==> Remove local build outputs"
rm -rf "${IOS_DIR}/build"
rm -rf "${IOS_DIR}"/DerivedData*

echo "==> Remove Xcode user-specific project state"
rm -rf "${IOS_DIR}/DreamWorkApp.xcodeproj/project.xcworkspace/xcuserdata"
rm -rf "${IOS_DIR}/DreamWorkApp.xcodeproj/xcuserdata"

echo "==> Remove DreamWork DerivedData (global)"
rm -rf "${HOME}/Library/Developer/Xcode/DerivedData"/DreamWorkApp-*

echo "==> Remove old DreamWork archives (unsigned/stale)"
if [[ -d "${HOME}/Library/Developer/Xcode/Archives" ]]; then
  find "${HOME}/Library/Developer/Xcode/Archives" -maxdepth 2 -name 'DreamWorkApp.xcarchive' -print -exec rm -rf {} + 2>/dev/null || true
fi

echo "==> Clear Xcode account portal cache (safe to rebuild on next sign-in)"
rm -rf "${HOME}/Library/Developer/Xcode/UserData/Capabilities" 2>/dev/null || true
rm -f "${HOME}/Library/Developer/Xcode/UserData/IDEPreferencesController.xcuserstate" 2>/dev/null || true

echo "==> Regenerate Xcode project from project.yml"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Install XcodeGen: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate

echo "==> Ensure Vendor frameworks"
if [[ ! -d "${IOS_DIR}/Vendor/llama.xcframework" ]]; then
  "${SCRIPT_DIR}/install-llama-xcframework.sh"
fi
if [[ ! -d "${IOS_DIR}/Vendor/onnxruntime.xcframework" ]] && [[ -f "${SCRIPT_DIR}/install-onnxruntime-xcframework.sh" ]]; then
  "${SCRIPT_DIR}/install-onnxruntime-xcframework.sh" || true
fi

echo ""
echo "Done. Local Xcode state reset."
echo ""
echo "Next (manual — required for signing):"
echo "  1. Open DreamWorkApp.xcodeproj"
echo "  2. Xcode → Settings → Accounts → remove and re-add gururakshe@icloud.com"
echo "  3. Download Manual Profiles"
echo "  4. DreamWorkApp target → Signing → Team: sreenivasulu kota (Admin)"
echo "  5. Destination: Any iOS Device → Product → Archive"
