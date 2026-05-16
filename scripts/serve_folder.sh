#!/usr/bin/env bash
set -euo pipefail

# Serve an arbitrary laptop folder over HTTP so the iOS app can fetch an ID image/PDF by URL.
# Usage:
#   ./scripts/serve_folder.sh "/path/to/folder" [port]
#
# Notes:
# - Simulator can use http://127.0.0.1:<port>/
# - Real iPhone/iPad must use http://<YOUR_MAC_WIFI_IP>:<port>/ (same Wi‑Fi)

DIR="${1:-$HOME/Downloads}"
PORT="${2:-8009}"

if [[ ! -d "$DIR" ]]; then
  echo "Folder not found: $DIR" >&2
  exit 2
fi

echo "Serving folder: $DIR"
echo "Port: $PORT"
echo
echo "In the iOS app (Scan → Browse laptop Downloads):"
echo "- Simulator: http://127.0.0.1:$PORT/"
echo "- Real iPhone/iPad: http://<YOUR_MAC_WIFI_IP>:$PORT/"
echo
echo "Mac Wi‑Fi IP (try these):"
ipconfig getifaddr en0 2>/dev/null | awk '{print " - en0: http://" $0 ":'"$PORT"'/" }' || true
ipconfig getifaddr en1 2>/dev/null | awk '{print " - en1: http://" $0 ":'"$PORT"'/" }' || true
echo
echo "Press Ctrl+C to stop."

cd "$DIR"
python3 -m http.server "$PORT" --bind 0.0.0.0

