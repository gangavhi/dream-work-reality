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
#   ./scripts/prepare_simulator_testing.sh [--servers-only] [simulator device name]
#   ./apps/ios/scripts/prepare-simulator-testing.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVERS_ONLY=0
DEVICE=""

for arg in "$@"; do
  case "${arg}" in
    --servers-only) SERVERS_ONLY=1 ;;
    *) DEVICE="${arg}" ;;
  esac
done

resolve_simulator_device() {
  if [[ -n "${DEVICE}" ]]; then
    echo "${DEVICE}"
    return
  fi
  local booted
  booted="$(xcrun simctl list devices booted 2>/dev/null | sed -n 's/^[[:space:]]*\(.*\) ([0-9A-F-]*) (Booted)$/\1/p' | head -1)"
  if [[ -n "${booted}" ]]; then
    echo "${booted}"
    return
  fi
  for candidate in "DreamWork iPhone" "iPhone 17" "iPhone 16"; do
    if xcrun simctl list devices available 2>/dev/null | grep -q "${candidate}"; then
      echo "${candidate}"
      return
    fi
  done
  echo "iPhone 17"
}

DEVICE="$(resolve_simulator_device)"
PID_DIR="${ROOT}/.simulator-test-pids"
mkdir -p "${PID_DIR}" "${ROOT}/demo/sample-documents"

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

if [[ "${SERVERS_ONLY}" -eq 0 ]]; then
  IOS_DIR="${ROOT}/apps/ios"
  if [[ -d "${IOS_DIR}/DreamWorkApp.xcodeproj" ]]; then
    echo "Building and launching DreamWork app on ${DEVICE}…"
    (
      cd "${IOS_DIR}"
      xcodegen generate >/dev/null 2>&1 || true
      xcodebuild -project DreamWorkApp.xcodeproj -scheme DreamWorkApp \
        -destination "platform=iOS Simulator,name=${DEVICE}" \
        -derivedDataPath ./DerivedData build >/dev/null
      xcrun simctl install booted ./DerivedData/Build/Products/Debug-iphonesimulator/DreamWorkApp.app
      xcrun simctl launch booted com.dream.nestledger.dev
    )
  fi
else
  echo "Skipping app build (--servers-only). Run from Xcode or omit the flag to auto-launch."
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
