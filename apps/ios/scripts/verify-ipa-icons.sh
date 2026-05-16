#!/usr/bin/env bash
# Usage: ./scripts/verify-ipa-icons.sh path/to/DreamWorkApp.ipa
set -euo pipefail
IPA="${1:?Usage: $0 path/to/DreamWorkApp.ipa}"
if [[ ! -f "${IPA}" ]]; then
  echo "error: IPA not found: ${IPA}" >&2
  echo "  If export failed (e.g. wrong Team ID or provisioning), there is no .ipa yet—fix export first." >&2
  echo "  After a successful archive script run, try: ${0} build/DreamWorkApp.ipa" >&2
  exit 1
fi
# Capture listing first: with `set -o pipefail`, `unzip -l | grep -q` can return
# unzip's SIGPIPE (e.g. 141) when grep exits early, falsely failing the check.
LISTING="$(unzip -l "$IPA")"
if ! echo "$LISTING" | grep -q 'Payload/[^/]*\.app/AppIcon60x60@2x\.png'; then
  echo "FAILED: AppIcon60x60@2x.png (120×120) missing from IPA." >&2
  exit 1
fi
if ! echo "$LISTING" | grep -q 'Payload/[^/]*\.app/Assets\.car'; then
  echo "WARNING: Assets.car missing (actool step may have been skipped)." >&2
fi
TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT
unzip -qq "${IPA}" 'Payload/*.app/Info.plist' -d "${TMP}"
INFO_PLIST="$(find "${TMP}/Payload" -name Info.plist 2>/dev/null | head -1 || true)"
if [[ -z "${INFO_PLIST}" || ! -f "${INFO_PLIST}" ]]; then
  echo "FAILED: could not extract Payload/*.app/Info.plist from IPA." >&2
  exit 1
fi
if ! /usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles:0' "${INFO_PLIST}" >/dev/null 2>&1; then
  echo "FAILED: Info.plist has no CFBundleIcons → CFBundlePrimaryIcon → CFBundleIconFiles (Apple 409: missing 120×120 reference)." >&2
  echo "  Fix: re-run archive-for-testflight.sh (post-build script must merge actool partial plist after deleting stale CFBundleIcons)." >&2
  exit 1
fi
if ! /usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' "${INFO_PLIST}" >/dev/null 2>&1; then
  echo "FAILED: Info.plist missing CFBundleIcons → CFBundlePrimaryIcon → CFBundleIconName." >&2
  exit 1
fi
echo "OK: IPA has AppIcon60x60@2x.png, CFBundleIconFiles, and CFBundleIconName (App Store icon checks)."
