#!/usr/bin/env bash
# Fix ONNX Runtime (and other) framework signatures inside an exported .ipa.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IPA="${1:-}"

if [[ -z "${IPA}" || ! -f "${IPA}" ]]; then
  echo "usage: ${0} /path/to/DreamWorkApp.ipa" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

unzip -q "${IPA}" -d "${TMP}"
APP="$(echo "${TMP}"/Payload/*.app)"
if [[ ! -d "${APP}" ]]; then
  echo "error: Payload/*.app not found in ${IPA}" >&2
  exit 1
fi

"${SCRIPT_DIR}/sign-embedded-frameworks.sh" "${APP}"

rm -f "${IPA}"
(
  cd "${TMP}"
  zip -qr "${IPA}" Payload
)

echo "Re-signed IPA: ${IPA}"
