#!/usr/bin/env bash
# Install the pinned llama.cpp XCFramework used by the iOS GGUF runtime integration.
#
# The binary itself is intentionally not committed. Re-run this script on any build
# machine before generating/building the Xcode project.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${IOS_DIR}/Vendor"
FRAMEWORK_DIR="${VENDOR_DIR}/llama.xcframework"
ZIP_PATH="${VENDOR_DIR}/llama-b5046-xcframework.zip"

# llama.cpp upstream example binary target from the XCFramework docs.
LLAMA_XCFRAMEWORK_URL="https://github.com/ggml-org/llama.cpp/releases/download/b5046/llama-b5046-xcframework.zip"
LLAMA_XCFRAMEWORK_SHA256="c19be78b5f00d8d29a25da41042cb7afa094cbf6280a225abe614b03b20029ab"

mkdir -p "${VENDOR_DIR}"

if [[ -d "${FRAMEWORK_DIR}" ]]; then
  echo "llama.xcframework already installed:"
  echo "  ${FRAMEWORK_DIR}"
  exit 0
fi

if [[ ! -f "${ZIP_PATH}" ]]; then
  echo "Downloading llama.cpp XCFramework..."
  curl -L "${LLAMA_XCFRAMEWORK_URL}" -o "${ZIP_PATH}"
fi

ACTUAL_SHA256="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
if [[ "${ACTUAL_SHA256}" != "${LLAMA_XCFRAMEWORK_SHA256}" ]]; then
  echo "error: llama.cpp XCFramework checksum mismatch" >&2
  echo "expected: ${LLAMA_XCFRAMEWORK_SHA256}" >&2
  echo "actual:   ${ACTUAL_SHA256}" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

unzip -q "${ZIP_PATH}" -d "${TMP_DIR}"
FOUND="$(find "${TMP_DIR}" -name 'llama.xcframework' -type d | head -1)"
if [[ -z "${FOUND}" ]]; then
  echo "error: zip did not contain llama.xcframework" >&2
  exit 1
fi

mv "${FOUND}" "${FRAMEWORK_DIR}"

echo "Installed llama.cpp XCFramework:"
echo "  ${FRAMEWORK_DIR}"
