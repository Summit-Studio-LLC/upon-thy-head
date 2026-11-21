#!/bin/bash
# Polish's light over the words (integration_test/polish_light_test.dart), filmed on the simulator
# with a stand-in for the phone's model. Three runs: as it is; with Reduce Motion; the app in
# Spanish at the largest text size. Reduce Motion, the text size and the app's language are set
# inside the simulator only, and put back when the script ends, however it ends.
#
#   tool/polish_light_walk.sh [simulator udid] [runs...]     runs: normal still es-ax (all by default)
#
# Films and screenshots: ../design/sim/polish-light/.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-52FB836B-4A44-4338-83D1-712E6580E91B}"
shift || true
RUNS="${*:-normal still es-ax}"
BUNDLE=dev.summitstudio.uponThyHead
OUT_DIR="$(cd .. && pwd)/design/sim/polish-light"
mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"

reduce_motion() { # true|false, for this simulator only
  xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool "$1" 2>/dev/null
  xcrun simctl spawn "$UDID" notifyutil -p com.apple.accessibility.reduce.motion.status 2>/dev/null
}
put_back() {
  reduce_motion false
  xcrun simctl ui "$UDID" content_size large 2>/dev/null || true
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLanguages 2>/dev/null || true
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLocale 2>/dev/null || true
}
trap put_back EXIT

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true

status=0
for run in $RUNS; do
  echo "== $run"
  put_back
  case "$run" in
    still) reduce_motion true ;; # the test falls back to Flutter's own flag if this does not reach the app
    es-ax)
      xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLanguages -array es
      xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLocale es_US
      xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large ;;
  esac
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  rm -f "$TMP/ok"
  timeout 600 lockf -t 3600 /tmp/upon-thy-head-build.lock \
    flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/polish_light_test.dart \
    --dart-define=LIGHT_RUN="$run" 2>&1 |
    while IFS= read -r line; do
      echo "$line"
      case "$line" in
        *"FILM START"*)
          xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT_DIR/$run.mp4" >/dev/null 2>&1 &
          echo $! > "$TMP/rec.pid" ;;
        *"FILM END"*)
          sleep 1; kill -INT "$(cat "$TMP/rec.pid")" 2>/dev/null; rm -f "$TMP/rec.pid"; sleep 2 ;;
        *SIMSHOT*)
          name="${line##*SIMSHOT polish-light/}"
          xcrun simctl io "$UDID" screenshot "$OUT_DIR/$name.png" >/dev/null 2>&1 ;;
        *"All tests passed"*) touch "$TMP/ok" ;;
      esac
    done
  [[ -f "$TMP/rec.pid" ]] && kill -INT "$(cat "$TMP/rec.pid")" 2>/dev/null
  rm -f "$TMP/rec.pid"
  if [[ -f "$TMP/ok" ]]; then echo "== $run PASSED"; else echo "== $run FAILED"; status=1; fi
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
done
exit $status
