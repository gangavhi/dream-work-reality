#!/usr/bin/env bash
# Download the pinned mobile-safe Qwen2.5 GGUF used by llm.schema.lite.v1.

set -euo pipefail

MODEL_REPO="bartowski/Qwen2.5-0.5B-Instruct-GGUF"
MODEL_FILE="Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}"
EXPECTED_SHA256="6eb923e7d26e9cea28811e1a8e852009b21242fb157b26149d3b188f3a8c8653"

BASE="${HOME}/Library/Application Support/DreamWork"
MODELS="${BASE}/models"

mkdir -p "${BASE}" "${MODELS}"

if [[ ! -f "${MODELS}/${MODEL_FILE}" ]]; then
  curl --fail --location --continue-at - \
    --output "${MODELS}/${MODEL_FILE}" \
    "${MODEL_URL}"
fi

ACTUAL_SHA256="$(shasum -a 256 "${MODELS}/${MODEL_FILE}" | awk '{print $1}')"
if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
  echo "error: SHA-256 mismatch for ${MODEL_FILE}" >&2
  echo "expected: ${EXPECTED_SHA256}" >&2
  echo "actual:   ${ACTUAL_SHA256}" >&2
  exit 1
fi

echo "Downloaded and verified:"
echo "  ${MODELS}/${MODEL_FILE}"
echo "  sha256=${ACTUAL_SHA256}"
