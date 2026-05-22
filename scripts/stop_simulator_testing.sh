#!/usr/bin/env bash
# Stop background HTTP servers started by prepare_simulator_testing.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_DIR="${ROOT}/.simulator-test-pids"

for name in sample-documents downloads; do
  pid_file="${PID_DIR}/${name}.pid"
  if [[ -f "${pid_file}" ]]; then
    pid="$(cat "${pid_file}")"
    if kill -0 "${pid}" 2>/dev/null; then
      echo "Stopping ${name} (pid ${pid})…"
      kill "${pid}" 2>/dev/null || true
    fi
    rm -f "${pid_file}"
  fi
done

for port in 8010 8009; do
  if lsof -ti ":${port}" >/dev/null 2>&1; then
    echo "Stopping process on port ${port}…"
    lsof -ti ":${port}" | xargs kill 2>/dev/null || true
  fi
done

echo "Done."
