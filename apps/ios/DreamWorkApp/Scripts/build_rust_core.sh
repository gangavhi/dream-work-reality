#!/bin/sh
set -eu

# Invoked from Xcode Run Script phase. Keeps variable expansion out of XcodeGen (which would otherwise mangle $HOME, etc.).

if [ "${ENABLE_PREVIEWS:-}" = "YES" ]; then
  exit 0
fi

if [ -f "${HOME}/.cargo/env" ]; then
  # shellcheck source=/dev/null
  . "${HOME}/.cargo/env"
fi

export CARGO_TARGET_DIR="${SRCROOT}/../../core/target"

rust_profile="debug"
if [ "${CONFIGURATION}" = "Release" ]; then
  rust_profile="release"
fi

targets=""
if [ "${PLATFORM_NAME}" = "iphonesimulator" ]; then
  case "${ARCHS:-}" in
    *x86_64*) targets="x86_64-apple-ios" ;;
    *) targets="aarch64-apple-ios-sim" ;;
  esac
else
  targets="aarch64-apple-ios"
fi

for rust_target in ${targets}; do
  rustup target add "${rust_target}" >/dev/null 2>&1 || true
  if [ "${rust_profile}" = "release" ]; then
    cargo build \
      --manifest-path "${SRCROOT}/../../core/dreamwork_core/Cargo.toml" \
      --target "${rust_target}" \
      --locked \
      --release
  else
    cargo build \
      --manifest-path "${SRCROOT}/../../core/dreamwork_core/Cargo.toml" \
      --target "${rust_target}" \
      --locked
  fi
done
