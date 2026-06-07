#!/usr/bin/env bash
# Convenience wrapper — run from apps/ios or repo root.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec "${ROOT}/scripts/prepare_simulator_testing.sh" "$@"
