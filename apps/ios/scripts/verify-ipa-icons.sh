#!/usr/bin/env bash
# Usage: ./scripts/verify-ipa-icons.sh path/to/DreamWorkApp.ipa
set -euo pipefail
IPA="${1:?Usage: $0 path/to/DreamWorkApp.ipa}"
if ! unzip -l "$IPA" | grep -q 'Payload/[^/]*\.app/AppIcon60x60@2x\.png'; then
  echo "FAILED: AppIcon60x60@2x.png (120×120) missing from IPA." >&2
  exit 1
fi
if ! unzip -l "$IPA" | grep -q 'Payload/[^/]*\.app/Assets\.car'; then
  echo "WARNING: Assets.car missing (actool step may have been skipped)." >&2
fi
echo "OK: IPA lists AppIcon60x60@2x.png (required for App Store validation)."
