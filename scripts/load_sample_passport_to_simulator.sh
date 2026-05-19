#!/usr/bin/env bash
# Load the US passport sample into the iOS Simulator Photos library for ingest testing.
#
# Usage:
#   ./scripts/load_sample_passport_to_simulator.sh [device name]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLE="${ROOT}/demo/sample-documents/us-passport-sample.png"
DEVICE="${1:-iPhone 17}"

if [[ ! -f "${SAMPLE}" ]]; then
  echo "error: passport sample missing at ${SAMPLE}" >&2
  echo "  Re-run from repo root after pulling latest, or create the sample PNG." >&2
  exit 1
fi

xcrun simctl boot "${DEVICE}" 2>/dev/null || true
open -a Simulator
xcrun simctl addmedia booted "${SAMPLE}"
echo "Added to Simulator Photos: ${SAMPLE}"
echo ""
echo "In DreamWork app:"
echo "  1. Home → Upload PDF or image → pick us-passport-sample from Photos"
echo "     OR Home → Browse laptop documents → us-passport-sample.png"
echo "  2. Review scan — expect Passport document type and fields like:"
echo "     • Full name / first / last"
echo "     • Passport number"
echo "     • Date of birth"
echo "     • Passport expiry"
