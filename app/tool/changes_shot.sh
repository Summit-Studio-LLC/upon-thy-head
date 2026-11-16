#!/bin/bash
# The sample's changes screen beside the prototype's, at the same scale (3 pixels to the point),
# tops aligned (the phone is 402 x 874 points, the prototype 390 x 844):
# ../design/sim/polish/16-sample-last-change.png and 17-side-by-side.png.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
OUT_DIR="$(cd .. && pwd)/design/sim/polish"
mkdir -p "$OUT_DIR"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
tool/sim_permissions.sh grant "$UDID" >/dev/null
timeout 400 flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/changes_shot_test.dart 2>&1 |
  while IFS= read -r line; do
    echo "$line"
    case "$line" in
      *SIMSHOT*) name="${line##*SIMSHOT }"; xcrun simctl io "$UDID" screenshot "$OUT_DIR/../$name.png" >/dev/null 2>&1 ;;
    esac
  done
ffmpeg -y -loglevel error -i "$(cd .. && pwd)/design/prototype/shots/05-review-changes.png" -i "$OUT_DIR/16-sample-last-change.png" \
  -filter_complex "[0]pad=iw+40:2622:0:0:color=0x333333[a];[a][1]hstack" "$OUT_DIR/17-side-by-side.png"
