#!/usr/bin/env bash
# Install LayoutLMv3 CoreML artifact for iOS bundling / simulator testing.
# Runs convert-layoutlmv3-to-coreml.sh when the artifact is missing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${HOME}/Library/Application Support/DreamWork/models"
ARTIFACT="${MODELS_DIR}/layoutlmv3.mlmodelc"

if [[ -d "${ARTIFACT}" ]]; then
  echo "LayoutLMv3 already installed: ${ARTIFACT}"
  exit 0
fi

echo "LayoutLMv3 not found — attempting CoreML conversion (requires Python 3.10–3.12)..."
if [[ -z "${PYTHON_BIN:-}" ]]; then
  for candidate in python3.11 python3.12 python3.10; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      PYTHON_BIN="$(command -v "${candidate}")"
      break
    fi
  done
  PYTHON_BIN="${PYTHON_BIN:-python3}"
fi
export PYTHON_BIN
echo "Using ${PYTHON_BIN} ($("${PYTHON_BIN}" -V 2>&1))"
if ! "${SCRIPT_DIR}/convert-layoutlmv3-to-coreml.sh"; then
  echo "warning: LayoutLMv3 conversion failed; app will use guarded spatial pairing fallback." >&2
  exit 0
fi

if [[ -d "${ARTIFACT}" ]]; then
  echo "Installed LayoutLMv3: ${ARTIFACT}"
else
  echo "warning: conversion finished but ${ARTIFACT} is missing." >&2
fi
