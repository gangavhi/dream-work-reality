#!/usr/bin/env bash
# Wrapper so you can run from repo root: ./scripts/verify-ipa-icons.sh apps/ios/build/DreamWorkApp.ipa
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${ROOT}/apps/ios/scripts/verify-ipa-icons.sh" "$@"
