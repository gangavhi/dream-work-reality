#!/usr/bin/env bash
# Serve demo/sample-documents for iOS Simulator ingest testing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${ROOT}/demo/sample-documents"
PORT="${1:-8010}"

if [[ ! -d "${DIR}" ]]; then
  echo "error: folder not found: ${DIR}" >&2
  exit 2
fi

echo "Serving sample documents: ${DIR}"
echo "Port: ${PORT}"
echo
echo "In Simulator → Home → Browse laptop documents"
echo "  http://127.0.0.1:${PORT}/"
echo
echo "Add test files (PNG, JPG, PDF) to demo/sample-documents/ and refresh in the app."
echo "Press Ctrl+C to stop."
echo

cd "${DIR}"
python3 -m http.server "${PORT}" --bind 127.0.0.1
