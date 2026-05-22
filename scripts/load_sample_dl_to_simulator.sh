#!/usr/bin/env bash
# Load a sample document image into the iOS Simulator Photos library for ingest testing.
#
# Usage:
#   ./scripts/load_sample_dl_to_simulator.sh [path/to/document.png] [device name]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLE="${1:-}"
DEVICE="${2:-iPhone 17}"

if [[ -z "${SAMPLE}" ]]; then
  SAMPLE="$(find "${ROOT}/demo/sample-documents" -maxdepth 1 \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) 2>/dev/null | head -1 || true)"
fi

if [[ -z "${SAMPLE}" || ! -f "${SAMPLE}" ]]; then
  echo "error: no sample image found." >&2
  echo "  Add a PNG/JPG to demo/sample-documents/ or pass a path:" >&2
  echo "  ${0} /path/to/your-driver-license.png" >&2
  exit 1
fi

xcrun simctl boot "${DEVICE}" 2>/dev/null || true
open -a Simulator
xcrun simctl addmedia booted "${SAMPLE}"
echo "Added to Simulator Photos: ${SAMPLE}"
echo ""
echo "In DreamWork app:"
echo "  1. Home → Browse laptop documents → pick your file"
echo "     OR Upload PDF or image → pick from Photos"
echo "  2. Review scan → confirm extracted fields"
