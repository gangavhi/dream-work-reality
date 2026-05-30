#!/usr/bin/env bash
# Re-sign embedded frameworks (especially ONNX Runtime SPM) for App Store / TestFlight.
#
# ONNX Runtime ships linker-signed (adhoc) inside onnxruntime.framework. Wrapping the
# .framework bundle is not enough — the inner Mach-O must be stripped and re-signed
# with the same Distribution identity as the host app.
#
# Usage:
#   sign-embedded-frameworks.sh /path/to/DreamWorkApp.app [signing-identity]
#
set -euo pipefail

APP="${1:-}"
IDENTITY="${2:-}"

if [[ -z "${APP}" || ! -d "${APP}" ]]; then
  echo "usage: ${0} /path/to/App.app [signing-identity]" >&2
  exit 1
fi

FRAMEWORKS_DIR="${APP}/Frameworks"
MIN_VER="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"

if [[ -z "${IDENTITY}" ]]; then
  IDENTITY="$(
    codesign -dvvv "${APP}" 2>&1 \
      | awk -F'=' '/^Authority=Apple Distribution/ { sub(/^Authority=/, ""); print; exit }'
  )"
fi
if [[ -z "${IDENTITY}" ]]; then
  IDENTITY="$(
    codesign -dvvv "${APP}" 2>&1 \
      | awk -F'=' '/^Authority=/ { sub(/^Authority=/, ""); print; exit }'
  )"
fi
if [[ -z "${IDENTITY}" ]]; then
  echo "error: could not determine signing identity for ${APP}" >&2
  exit 1
fi

if [[ ! -d "${FRAMEWORKS_DIR}" ]]; then
  exit 0
fi

for fw in onnxruntime onnxruntime_extensions; do
  PLIST="${FRAMEWORKS_DIR}/${fw}.framework/Info.plist"
  if [[ -f "${PLIST}" ]]; then
    /usr/libexec/PlistBuddy -c "Delete :MinimumOSVersion" "${PLIST}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string ${MIN_VER}" "${PLIST}" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion ${MIN_VER}" "${PLIST}"
  fi
done

sign_binary() {
  local target="$1"
  /usr/bin/codesign --remove-signature "${target}" 2>/dev/null || true
  /usr/bin/codesign --force --sign "${IDENTITY}" \
    --timestamp \
    --options runtime \
    --generate-entitlement-der \
    "${target}"
}

for framework in "${FRAMEWORKS_DIR}"/*.framework; do
  [[ -d "${framework}" ]] || continue
  name="$(basename "${framework}" .framework)"
  binary="${framework}/${name}"
  echo "Re-signing ${name}.framework with ${IDENTITY}"
  if [[ -f "${binary}" ]]; then
    sign_binary "${binary}"
  fi
  sign_binary "${framework}"
done

/usr/bin/codesign --force --sign "${IDENTITY}" \
  --timestamp \
  --options runtime \
  --preserve-metadata=entitlements,requirements,flags,identifier \
  --generate-entitlement-der \
  "${APP}"

for framework in "${FRAMEWORKS_DIR}"/*.framework; do
  [[ -d "${framework}" ]] || continue
  name="$(basename "${framework}" .framework)"
  binary="${framework}/${name}"
  if [[ -f "${binary}" ]]; then
    codesign --verify --strict --verbose=2 "${binary}"
  fi
done
codesign --verify --deep --strict --verbose=2 "${APP}"
echo "OK: embedded frameworks satisfy strict code requirements"
