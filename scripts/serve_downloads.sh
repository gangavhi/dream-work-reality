#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-8009}"
DIR="$HOME/Downloads"

if [[ ! -d "$DIR" ]]; then
  echo "Downloads folder not found: $DIR" >&2
  exit 2
fi

echo "Serving $DIR on port $PORT"
echo
echo "In the iOS app:"
echo "- Tap Scan ID"
echo "- In 'Browse laptop Downloads' enter:"
echo "  - Simulator: http://127.0.0.1:$PORT/"
echo "  - Real iPhone/iPad: http://<YOUR_MAC_WIFI_IP>:$PORT/"
echo
echo "Mac Wi‑Fi IP (try these):"
ipconfig getifaddr en0 2>/dev/null | awk '{print " - en0: http://" $0 ":'"$PORT"'/" }' || true
ipconfig getifaddr en1 2>/dev/null | awk '{print " - en1: http://" $0 ":'"$PORT"'/" }' || true
echo
echo "Press Ctrl+C to stop."
cd "$DIR"
python3 -m http.server "$PORT" --bind 0.0.0.0

