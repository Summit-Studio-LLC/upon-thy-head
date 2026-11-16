#!/usr/bin/env bash
# Films an integration test on the simulator, from its DEMO START to its DEMO END log line.
#
#   tool/film.sh <test file> <output .mp4> [extra flutter drive args...]
#
# e.g. tool/film.sh integration_test/ring_demo_test.dart ../design/sim/ring/ring.mp4 --dart-define=DEMO=ring
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="$1"; OUT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2
UDID="${UDID:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
RAW="$(mktemp -d)/raw.mp4"

xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true

flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target="$TARGET" "$@" 2>&1 | while IFS= read -r line; do
  echo "$line"
  case "$line" in
    *"DEMO START"*)
      xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$RAW" >/dev/null 2>&1 &
      echo $! > "$RAW.pid" ;;
    *"DEMO END"*)
      kill -INT "$(cat "$RAW.pid")"; sleep 2 ;;
  esac
done

# a phone-sized, web-friendly copy
ffmpeg -y -loglevel error -i "$RAW" -vf "scale=804:-2,fps=30" -c:v libx264 -pix_fmt yuv420p -crf 22 -movflags +faststart "$OUT"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT"
