#!/bin/bash
# The life of a blessing across real restarts (integration_test/store_test.dart).
#
#   tool/store_lifecycle.sh [simulator udid]
#
# Runs the test three times with --keep-app-running (otherwise flutter drive
# uninstalls the app, and its data, when done). Between runs the app process is killed with
# `xcrun simctl terminate`; the next `flutter drive` installs over it (which
# keeps the app's data) and launches a new process, so each part reads the
# store from disk. Screenshots: ../design/sim/store/ (or $SIM_DIR/store/).
set -euo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
export SIM_SHOTS=1 # screenshots are the simulator's own, taken below when the test prints SIMSHOT
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
# start from part 1: forget any half-finished earlier run
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)"
[[ -n "$DATA" ]] && rm -f "$DATA/Documents/store_test_phase"
# the recording in part 1 needs the microphone and speech permission; `flutter drive` installs
# over this install, which keeps them
flutter build ios --simulator --debug >/dev/null
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
tool/sim_permissions.sh grant "$UDID"
for part in 1 2 3; do
  echo "== part $part"
  flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/store_test.dart --keep-app-running 2>&1 |
    while IFS= read -r line; do
      echo "$line"
      if [[ "$line" == *SIMSHOT* ]]; then
        name="${line##*SIMSHOT }"
        mkdir -p "${SIM_DIR:-../design/sim}/$(dirname "$name")"
        xcrun simctl io "$UDID" screenshot "${SIM_DIR:-../design/sim}/$name.png" >/dev/null 2>&1
      fi
    done
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  echo "== terminated $BUNDLE"
done
