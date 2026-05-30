#!/usr/bin/env bash
# Install Microsoft's ONNX Runtime iOS xcframework for App Store–compatible embedding.
#
# The SPM package embeds a linker-signed (adhoc) onnxruntime binary that fails
# App Store validation (ITMS-90035). This xcframework ships unsigned Mach-O
# binaries that Xcode signs on export — same pattern as Vendor/llama.xcframework.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${IOS_DIR}/Vendor"
FRAMEWORK_DIR="${VENDOR_DIR}/onnxruntime.xcframework"
ZIP_PATH="${VENDOR_DIR}/pod-archive-onnxruntime-c-1.24.2.zip"

ORT_POD_URL="https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.24.2.zip"
ORT_POD_SHA256="f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54"

mkdir -p "${VENDOR_DIR}"

if [[ ! -d "${FRAMEWORK_DIR}" ]]; then
  if [[ ! -f "${ZIP_PATH}" ]]; then
    echo "Downloading ONNX Runtime iOS pod archive (~50 MB)..."
    curl --fail --location --continue-at - -o "${ZIP_PATH}" "${ORT_POD_URL}"
  fi

  ACTUAL_SHA256="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
  if [[ "${ACTUAL_SHA256}" != "${ORT_POD_SHA256}" ]]; then
    echo "error: ONNX Runtime pod archive checksum mismatch" >&2
    echo "expected: ${ORT_POD_SHA256}" >&2
    echo "actual:   ${ACTUAL_SHA256}" >&2
    exit 1
  fi

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TMP_DIR}"' EXIT

  unzip -q "${ZIP_PATH}" -d "${TMP_DIR}"
  FOUND="$(find "${TMP_DIR}" -name 'onnxruntime.xcframework' -type d | head -1)"
  if [[ -z "${FOUND}" ]]; then
    echo "error: pod archive did not contain onnxruntime.xcframework" >&2
    exit 1
  fi

  mv "${FOUND}" "${FRAMEWORK_DIR}"
  echo "Installed ONNX Runtime xcframework:"
  echo "  ${FRAMEWORK_DIR}"
else
  echo "onnxruntime.xcframework already installed:"
  echo "  ${FRAMEWORK_DIR}"
fi

BINDINGS_DIR="${VENDOR_DIR}/onnxruntime-bindings"
if [[ ! -d "${BINDINGS_DIR}/include" ]]; then
  echo "Installing ONNX Runtime Objective-C bindings..."
  BINDINGS_TMP="$(mktemp -d)"
  curl --fail --location \
    "https://github.com/microsoft/onnxruntime-swift-package-manager/archive/refs/tags/1.24.2.tar.gz" \
    | tar -xz -C "${BINDINGS_TMP}"
  rm -rf "${BINDINGS_DIR}"
  mv "${BINDINGS_TMP}/onnxruntime-swift-package-manager-1.24.2/objectivec" "${BINDINGS_DIR}"
  rm -rf "${BINDINGS_TMP}"
  echo "Installed ONNX Runtime bindings:"
  echo "  ${BINDINGS_DIR}"
else
  echo "onnxruntime-bindings already installed:"
  echo "  ${BINDINGS_DIR}"
fi
