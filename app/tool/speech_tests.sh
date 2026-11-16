#!/bin/bash
# The speech tests on a simulator, with real permissions and the simulator's own screenshots.
#
#   tool/speech_tests.sh [simulator udid]
#
# 1. integration_test/speech_engine_test.dart: the prepared English and Spanish recordings
#    through the native transcription; prints the words, word errors and timings.
# 2. integration_test/speech_test.dart with permissions granted: the whole flow.
# 3. the same test with permissions refused: the refused state.
# `flutter drive` removes the app when it finishes, and permissions belong to the installed app,
# so before each run the app is installed and the permissions set (tool/sim_permissions.sh).
# Screenshots: ../design/sim/speech/ (or $SIM_DIR/speech/).
set -euo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
AUDIO="$PWD/integration_test/audio"
export SIM_SHOTS=1
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
flutter build ios --simulator --debug --dart-define=SPEECH_AUDIO="$AUDIO" >/dev/null

drive() { # target, permissions, extra defines...
  local target="$1" perms="$2"
  shift 2
  xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
  tool/sim_permissions.sh "$perms" "$UDID"
  echo "== $target ($perms)"
  flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target="$target" \
    --dart-define=SPEECH_AUDIO="$AUDIO" "$@" 2>&1 |
    while IFS= read -r line; do
      echo "$line"
      if [[ "$line" == *SIMSHOT* ]]; then
        name="${line##*SIMSHOT }"
        mkdir -p "${SIM_DIR:-../design/sim}/$(dirname "$name")"
        xcrun simctl io "$UDID" screenshot "${SIM_DIR:-../design/sim}/$name.png" >/dev/null 2>&1
      fi
    done
}

drive integration_test/speech_engine_test.dart grant
drive integration_test/speech_test.dart grant
drive integration_test/speech_test.dart deny --dart-define=SPEECH_REFUSED=true
