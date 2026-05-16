#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/core"

PORT="${PORT:-8080}"
HOST="${HOST:-127.0.0.1}"

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is already in use. Free it or run with PORT=8081." >&2
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN || true
  exit 1
fi

cd "$CORE_DIR"
cargo build -p core_api
exec ./target/debug/core_api

