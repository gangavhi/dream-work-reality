#!/usr/bin/env bash
# Copy the pinned GGUF models into the booted iOS simulator app sandbox.
#
# Prerequisite: install/run DreamWorkApp in the simulator at least once.

set -euo pipefail

BUNDLE_ID="${BUNDLE_ID:-com.dream.nestledger.dev}"
MODEL_DIR="${HOME}/Library/Application Support/DreamWork/models"
MODEL_FILES=(
  "Qwen2.5-3B-Instruct-Q4_K_M.gguf"
  "SS-350M-SQL-Strict.Q8_0.gguf"
)

for model_file in "${MODEL_FILES[@]}"; do
  if [[ ! -f "${MODEL_DIR}/${model_file}" ]]; then
    echo "error: model not found at ${MODEL_DIR}/${model_file}" >&2
    echo "Run apps/ios/scripts/download-qwen-gguf-model.sh and apps/ios/scripts/download-storage-planner-gguf-model.sh first." >&2
    exit 1
  fi
done

APP_DATA="$(xcrun simctl get_app_container booted "${BUNDLE_ID}" data)"
DEST_DIR="${APP_DATA}/Library/Application Support/DreamWork/models"
mkdir -p "${DEST_DIR}"
for model_file in "${MODEL_FILES[@]}"; do
  cp -f "${MODEL_DIR}/${model_file}" "${DEST_DIR}/${model_file}"
done

echo "Installed GGUF into simulator sandbox:"
for model_file in "${MODEL_FILES[@]}"; do
  echo "  ${DEST_DIR}/${model_file}"
done
