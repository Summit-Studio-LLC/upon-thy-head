#!/bin/bash
# "Your links": the Stop question and a stopped link's row, in English and Spanish, on the clean
# iPhone simulator (integration_test/your_links_shot_test.dart). Screenshots, the simulator's own,
# continue ../design/sim/link/'s numbering: 45 to 48.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
OUT_DIR="$(cd .. && pwd)/design/sim/link"
mkdir -p "$OUT_DIR"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
tool/sim_permissions.sh grant "$UDID" >/dev/null
n=44
perl -e 'alarm 600; exec @ARGV' flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/your_links_shot_test.dart 2>&1 |
  while IFS= read -r line; do
    echo "$line"
    case "$line" in
      *SIMSHOT*) n=$((n + 1)); name="${line##*SIMSHOT }"; xcrun simctl io "$UDID" screenshot "$OUT_DIR/$n-$name.png" >/dev/null 2>&1 ;;
    esac
  done
