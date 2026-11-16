#!/bin/bash
# The owner's rulings of 2026-11-15 on drafts, tags, listening in the background and words tried
# again (integration_test/drafts_test.dart).
#
#   tool/drafts_acceptance.sh [simulator udid]
#
# Two phases with --keep-app-running; between them the app is terminated, so the second is a new
# launch reading the store from disk. When the test prints BACKGROUND, this script opens the
# Settings app (the blessing app goes to the background, as with the Home button) and, at
# FOREGROUND, opens the app again. Permissions are granted before every phase; every phase has a
# time limit.
#
# Screenshots: ../design/sim/polish/.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
AUDIO="$PWD/integration_test/audio"
OUT_DIR="$(cd .. && pwd)/design/sim/polish"
LIMIT="${LIMIT:-420}"
mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$UDID" content_size large || true
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)"
[[ -n "$DATA" ]] && rm -f "$DATA/Documents/drafts_test_phase"
timeout 600 flutter build ios --simulator --debug --dart-define=SPEECH_AUDIO="$AUDIO" >/dev/null || { echo "build failed"; exit 1; }
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
status=1
for run in 1 2 3; do
  echo "== run $run"
  tool/sim_permissions.sh grant "$UDID" >/dev/null
  rm -f "$TMP/done" "$TMP/failed"
  timeout "$LIMIT" flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/drafts_test.dart \
    --dart-define=SPEECH_AUDIO="$AUDIO" --keep-app-running 2>&1 |
    while IFS= read -r line; do
      echo "$line"
      case "$line" in
        "flutter: BACKGROUND"*) sleep 0.5; xcrun simctl launch "$UDID" com.apple.Preferences >/dev/null; echo "== opened Settings" ;;
        "flutter: FOREGROUND"*) xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null; echo "== opened the app again" ;;
        *"ALL DONE"*) touch "$TMP/done" ;;
        *"Some tests failed"*|*"[E]"*) touch "$TMP/failed" ;;
        *SIMSHOT*)
          name="${line##*SIMSHOT }"
          xcrun simctl io "$UDID" screenshot "$OUT_DIR/../$name.png" >/dev/null 2>&1 ;;
      esac
    done
  if [[ -f "$TMP/failed" ]]; then echo "== run $run FAILED"; break; fi
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  echo "== terminated $BUNDLE"
  if [[ -f "$TMP/done" ]]; then status=0; echo "== ALL PHASES PASSED"; break; fi
  sleep 2
done
exit $status
