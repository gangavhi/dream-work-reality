#!/usr/bin/env bash
# Download the pinned Qwen2.5 3B GGUF used by llm.schema.lite.v1.

set -euo pipefail

MODEL_REPO="bartowski/Qwen2.5-3B-Instruct-GGUF"
MODEL_FILE="Qwen2.5-3B-Instruct-Q4_K_M.gguf"
EXPECTED_SHA256="9c9f56a391a3abbd5b89d0245bf6106081bcc3173119d4229235dd9d23253f94"

BASE="${HOME}/Library/Application Support/DreamWork"
VENV="${BASE}/hf-venv"
MODELS="${BASE}/models"

mkdir -p "${BASE}" "${MODELS}"

if [[ ! -x "${VENV}/bin/hf" ]]; then
  python3 -m venv "${VENV}"
  "${VENV}/bin/python" -m pip install -U pip huggingface_hub
fi

"${VENV}/bin/hf" download "${MODEL_REPO}" \
  --include "${MODEL_FILE}" \
  --local-dir "${MODELS}"

ACTUAL_SHA256="$(shasum -a 256 "${MODELS}/${MODEL_FILE}" | awk '{print $1}')"
if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
  echo "error: SHA-256 mismatch for ${MODEL_FILE}" >&2
  echo "expected: ${EXPECTED_SHA256}" >&2
  echo "actual:   ${ACTUAL_SHA256}" >&2
  exit 1
fi

echo "Downloaded and verified:"
echo "  ${MODELS}/${MODEL_FILE}"
