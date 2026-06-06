#!/usr/bin/env bash
# Run Vision OCR + pipeline E2E tests on iOS Simulator fixtures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${IOS_DIR}"

SIMULATOR_ID="${SIMULATOR_ID:-7FA77B9B-6087-4E06-823D-297F4D68C395}"
FIXTURE="${IOS_DIR}/DreamWorkAppTests/Fixtures/texas-driver-license-sample.png"
SRC_ASSET="${SRC_ASSET:-}"

if [[ ! -f "${FIXTURE}" && -n "${SRC_ASSET}" && -f "${SRC_ASSET}" ]]; then
  echo "==> Converting fixture from ${SRC_ASSET}"
  sips -s format png "${SRC_ASSET}" --out "${FIXTURE}" >/dev/null
fi

if [[ ! -f "${FIXTURE}" ]]; then
  echo "error: Missing ${FIXTURE}" >&2
  echo "  Copy a Texas DL photo there, or set SRC_ASSET=/path/to/image.png" >&2
  exit 1
fi

echo "==> xcodegen generate"
xcodegen generate

echo "==> Running lifecycle + fixture simulator OCR E2E tests"
xcodebuild test \
  -scheme DreamWorkApp \
  -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
  -only-testing:DreamWorkAppTests/LifecycleDocumentSimulationTests \
  -only-testing:DreamWorkAppTests/SimulatorDocumentPipelineE2ETests
