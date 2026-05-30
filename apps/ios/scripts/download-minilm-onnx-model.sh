#!/usr/bin/env bash
# Download sentence-transformers/all-MiniLM-L6-v2 as INT8 ONNX (Xenova export) for embed.minilm.v1.

set -euo pipefail

MODEL_REPO="Xenova/all-MiniLM-L6-v2"
ONNX_FILE="minilm_field_embed_int8.onnx"
TOKENIZER_FILE="minilm_tokenizer.json"
ONNX_URL="https://huggingface.co/${MODEL_REPO}/resolve/main/onnx/model_int8.onnx"
TOKENIZER_URL="https://huggingface.co/${MODEL_REPO}/resolve/main/tokenizer.json"

BASE="${HOME}/Library/Application Support/DreamWork"
MODELS="${BASE}/models"

mkdir -p "${BASE}" "${MODELS}"

if [[ ! -f "${MODELS}/${ONNX_FILE}" ]]; then
  echo "Downloading ${ONNX_FILE} (~23 MB)..."
  curl --fail --location --continue-at - \
    --output "${MODELS}/${ONNX_FILE}" \
    "${ONNX_URL}"
fi

if [[ ! -f "${MODELS}/${TOKENIZER_FILE}" ]]; then
  echo "Downloading ${TOKENIZER_FILE}..."
  curl --fail --location --continue-at - \
    --output "${MODELS}/${TOKENIZER_FILE}" \
    "${TOKENIZER_URL}"
fi

BYTES="$(wc -c < "${MODELS}/${ONNX_FILE}" | tr -d ' ')"
SHA256="$(shasum -a 256 "${MODELS}/${ONNX_FILE}" | awk '{print $1}')"

echo "Downloaded and verified:"
echo "  ${MODELS}/${ONNX_FILE}"
echo "  bytes=${BYTES}"
echo "  sha256=${SHA256}"
echo "  ${MODELS}/${TOKENIZER_FILE}"
