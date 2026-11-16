#!/bin/bash
# The phone check page on a simulator: integration_test/phone_check_test.dart in a PHONE_CHECK build.
#
#   tool/phone_check_sim.sh [simulator udid]
#
# Permissions are granted (tool/sim_permissions.sh) and the simulator is given a place near Salt Lake
# City, so the location check has something to find. Screenshots: ../design/sim/phone-check/.
set -euo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl location "$UDID" set 40.7608,-111.8910 || true
flutter build ios --simulator --debug --dart-define=PHONE_CHECK=true >/dev/null
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
tool/sim_permissions.sh grant "$UDID"
flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/phone_check_test.dart \
  --dart-define=PHONE_CHECK=true 2>&1 |
  while IFS= read -r line; do
    echo "$line"
    if [[ "$line" == *SIMSHOT* ]]; then
      name="${line##*SIMSHOT }"
      mkdir -p "../design/sim/$(dirname "$name")"
      xcrun simctl io "$UDID" screenshot "../design/sim/$name.png" >/dev/null 2>&1
    fi
  done
