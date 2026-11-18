#!/bin/bash
# Every integration test on a simulator, with microphone and speech permission granted.
#
#   tool/integration_tests.sh [simulator udid]
#
# `flutter drive` installs over the app, which keeps the permissions set here; the recording
# screen needs them for Begin. The speech tests (tool/speech_tests.sh), the real-microphone
# test (tool/microphone_test.sh) and the store's restart test (tool/store_lifecycle.sh) have
# their own scripts. Screenshots are not retaken here.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
flutter build ios --simulator --debug >/dev/null || exit 1
failed=()
for t in home record reduce_motion ring ring_demo store_demo zoom screen_reader; do
  xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
  tool/sim_permissions.sh grant "$UDID" >/dev/null
  echo "== $t"
  out="$(flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target="integration_test/${t}_test.dart" 2>&1)"
  code=$?
  grep -E "All tests passed|Some tests failed|EXCEPTION|Expected:|Actual:" <<<"$out"
  [[ $code -eq 0 ]] && grep -q "All tests passed" <<<"$out" || failed+=("$t")
done
echo "FAILED: ${failed[*]:-none}"
[[ ${#failed[@]} -eq 0 ]]
