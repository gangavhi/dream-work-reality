#!/usr/bin/env bash
# Prepare iOS Simulator for document ingest testing from your Mac.
#
# Starts HTTP servers for:
#   - demo/sample-documents  → http://127.0.0.1:8010/
#   - ~/Downloads            → http://127.0.0.1:8009/
#
# Add your own PNG/JPG/PDF files to demo/sample-documents/ before running.
#
# Usage:
#   ./scripts/prepare_simulator_testing.sh [device name]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-iPhone 17}"
PID_DIR="${ROOT}/.simulator-test-pids"
mkdir -p "${PID_DIR}"

stop_port() {
  local port="$1"
  if lsof -ti ":${port}" >/dev/null 2>&1; then
    echo "Stopping existing server on port ${port}…"
    lsof -ti ":${port}" | xargs kill 2>/dev/null || true
    sleep 0.5
  fi
}

start_server() {
  local name="$1"
  local script="$2"
  local port="$3"
  local log="${PID_DIR}/${name}.log"
  stop_port "${port}"
  echo "Starting ${name} on port ${port}…"
  nohup bash "${script}" "${port}" >"${log}" 2>&1 &
  echo $! > "${PID_DIR}/${name}.pid"
}

start_server "sample-documents" "${ROOT}/scripts/serve_sample_documents.sh" 8010
start_server "downloads" "${ROOT}/scripts/serve_downloads.sh" 8009

echo "Booting Simulator (${DEVICE})…"
xcrun simctl boot "${DEVICE}" 2>/dev/null || true
open -a Simulator

SAMPLE_DIR="${ROOT}/demo/sample-documents"
FIRST_IMAGE="$(find "${SAMPLE_DIR}" -maxdepth 1 \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) 2>/dev/null | head -1 || true)"
if [[ -n "${FIRST_IMAGE}" ]]; then
  echo "Adding sample image to Simulator Photos: $(basename "${FIRST_IMAGE}")"
  xcrun simctl addmedia booted "${FIRST_IMAGE}" 2>/dev/null || xcrun simctl addmedia "${DEVICE}" "${FIRST_IMAGE}" || true
fi

IOS_DIR="${ROOT}/apps/ios"
if [[ -d "${IOS_DIR}/DreamWorkApp.xcodeproj" ]]; then
  echo "Building and launching DreamWork app…"
  (
    cd "${IOS_DIR}"
    xcodebuild -project DreamWorkApp.xcodeproj -scheme DreamWorkApp \
      -destination "platform=iOS Simulator,name=${DEVICE}" \
      -derivedDataPath ./DerivedData build >/dev/null
    xcrun simctl install booted ./DerivedData/Build/Products/Debug-iphonesimulator/DreamWorkApp.app
    xcrun simctl launch booted com.dream.nestledger.dev
  )
fi

echo ""
echo "Ready to test."
echo ""
echo "In the app (Simulator):"
echo "  1. Home → Browse laptop documents"
echo "  2. Pick a document from Project sample documents or Downloads"
echo "  3. Review scan → confirm fields map correctly"
echo ""
echo "Add test files to: ${SAMPLE_DIR}/"
echo "Or drop any PDF/image from Finder onto the Simulator window."
echo ""
echo "Servers (logs in ${PID_DIR}/):"
echo "  Sample docs: http://127.0.0.1:8010/"
echo "  Downloads:   http://127.0.0.1:8009/"
echo ""
echo "Stop servers: ./scripts/stop_simulator_testing.sh"
