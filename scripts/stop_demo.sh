#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_DIR="$ROOT_DIR/.demo-pids"

echo "==> Stopping demo background services"

if [[ -f "$PID_DIR/port-forward.pid" ]]; then
  kill "$(cat "$PID_DIR/port-forward.pid")" >/dev/null 2>&1 || true
fi
pkill -f "kubectl port-forward service/core-api 18081:8080" >/dev/null 2>&1 || true

if [[ -f "$PID_DIR/form-server.pid" ]]; then
  kill "$(cat "$PID_DIR/form-server.pid")" >/dev/null 2>&1 || true
fi
pkill -f "python3 -m http.server 8000" >/dev/null 2>&1 || true

echo "Stopped. Logs (if any) are under: $PID_DIR"
