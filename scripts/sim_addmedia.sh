#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF >&2
Usage:
  $0 /path/to/file.(png|jpg|jpeg)
  $0 --latest-download

Adds an image to the booted iOS Simulator Photos library so the app can
scan it via "Scan ID" -> "Choose Photo".
EOF
}

pick_latest_download() {
  local downloads="$HOME/Downloads"
  if [[ ! -d "$downloads" ]]; then
    echo "Downloads folder not found: $downloads" >&2
    exit 2
  fi

  # Pick newest common image type
  local file
  file="$(ls -t "$downloads"/*.{png,jpg,jpeg} 2>/dev/null | head -n 1 || true)"
  if [[ -z "$file" ]]; then
    echo "No .png/.jpg/.jpeg found in $downloads" >&2
    exit 2
  fi
  echo "$file"
}

FILE=""
if [[ $# -eq 1 && "$1" == "--latest-download" ]]; then
  FILE="$(pick_latest_download)"
elif [[ $# -eq 1 ]]; then
  FILE="$1"
else
  usage
  exit 2
fi

if [[ ! -f "$FILE" ]]; then
  echo "File not found: $FILE" >&2
  exit 2
fi

UDID="$(xcrun simctl list devices booted | awk -F '[()]' 'NR==1{print $2}')"
if [[ -z "$UDID" ]]; then
  # Fall back to any DreamWork iPhone if none booted
  UDID="$(xcrun simctl list devices | awk -F '[()]' '/DreamWork iPhone/ {print $2; exit}')"
fi

if [[ -z "$UDID" ]]; then
  echo "No simulator device found. Boot a simulator first." >&2
  exit 1
fi

echo "Adding media to simulator: $UDID"
echo "File: $FILE"
xcrun simctl addmedia "$UDID" "$FILE"
echo "Done. In the app tap Scan ID -> Choose Photo and select it."

