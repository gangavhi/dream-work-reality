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
echo "- In 'Load from laptop URL' enter: http://127.0.0.1:$PORT/<filename>"
echo
echo "Press Ctrl+C to stop."
cd "$DIR"
python3 -m http.server "$PORT"

