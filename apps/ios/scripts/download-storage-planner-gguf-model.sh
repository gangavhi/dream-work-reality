#!/usr/bin/env bash
# Download the local SQL/storage planner GGUF used by sql.storage.planner.v1.

set -euo pipefail

MODEL_REPO="saadxsalman/SS-350M-SQL-Strict-GGUF"
MODEL_FILE="SS-350M-SQL-Strict.Q8_0.gguf"
MODEL_URL="https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}"
EXPECTED_SHA256="9d1b6a05358c5df61f7c7089a382a1890aa9dedd098425d66a6d26f80623a40b"

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

echo "Downloaded storage planner model:"
echo "  ${MODELS}/${MODEL_FILE}"
