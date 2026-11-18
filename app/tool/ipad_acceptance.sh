#!/bin/bash
# The iPad pass (integration_test/ipad_test.dart) on an iPad simulator: every main screen in portrait,
# then landscape, with real rotations, the real system share sheet and the real lock.
#
#   tool/ipad_acceptance.sh [simulator udid] [shots folder]
#   LAST=1 tool/ipad_acceptance.sh <udid> 13     phase 1 only, screenshots in design/sim/ipad/13/
#   FIRST=2 tool/ipad_acceptance.sh              from phase 2 (Spanish) on
#
# Defaults: the first "iPad Air 11-inch (M3)" simulator, design/sim/ipad/. The simulator is booted if it is not, and
# shut down at the end only if this script booted it. Each phase is a new launch (--keep-app-running):
#   1  English: the first run, then the seeded app, portrait then landscape; review rotated with
#      words typed (nothing lost); text and PDF through the system share sheet; the lock
#   2  Spanish (the app's own language, as iOS Settings > Upon Thy Head > Language sets it; the
#      simulator's and the Mac's languages are left alone)
#   3  the largest text size
# Rotations come from tool/alerts (a UI test that runs alongside, `orient`). Built with SPEECH_AUDIO
# (the recording hears the English passage). Every build and run takes the shared build lock.
set -uo pipefail
cd "$(dirname "$0")/.."
# default: the first simulator named "iPad Air 11-inch (M3)…"
UDID="${1:-$(xcrun simctl list devices | grep -m1 'iPad Air 11-inch (M3)' | grep -oE '[0-9A-F-]{36}')}"
[[ -n "$UDID" ]] || { echo "no iPad Air 11-inch (M3) simulator; pass a udid"; exit 1; }
SUB="${2:-}"
BUNDLE=dev.summitstudio.uponThyHead
AUDIO="$PWD/integration_test/audio"
OUT_DIR="$(cd .. && pwd)/design/sim/ipad${SUB:+/$SUB}"
LIMIT="${LIMIT:-1700}" # seconds per phase
LAST="${LAST:-3}"
FIRST="${FIRST:-1}" # FIRST=2: start at Spanish (phase 1 already passed)
LOCK=/tmp/upon-thy-head-build.lock
TAP_DIR="${TMPDIR:-/tmp}/uth_tapper_ipad_$UDID"
DD="${TMPDIR:-/tmp}/uth_tapper_dd_ipad"
TMP="$(mktemp -d)"
mkdir -p "$OUT_DIR/es" "$OUT_DIR/ax"
[[ "$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n')" == *'"en-US"'* ]] || echo "== note: the Mac's own first language is not en-US (left alone)"

booted_here=0
state="$(xcrun simctl list devices | grep "$UDID" || true)"
if [[ "$state" != *Booted* ]]; then
  xcrun simctl boot "$UDID"; booted_here=1
fi
timeout 300 xcrun simctl bootstatus "$UDID" -b >/dev/null || { echo "the simulator did not boot"; exit 1; }
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$UDID" content_size large || true
# both kinds of iPad: a face (Face ID models) and a finger (Touch ID models) enrolled
xcrun simctl spawn "$UDID" notifyutil -s com.apple.BiometricKit.enrollmentChanged 1
xcrun simctl spawn "$UDID" notifyutil -p com.apple.BiometricKit.enrollmentChanged

# ---- the tapper (rotation, the share sheet) ----
lockf -t 3600 "$LOCK" timeout 900 xcodebuild build-for-testing -project tool/alerts/Tapper.xcodeproj -scheme TapperUITests \
  -destination "id=$UDID" -derivedDataPath "$DD" >"$TMP/tapper_build.txt" 2>&1 || { echo "tapper build failed"; tail -20 "$TMP/tapper_build.txt"; exit 1; }
XCTESTRUN="$(ls "$DD"/Build/Products/*.xctestrun | head -1)"
rm -rf "$TAP_DIR"; mkdir -p "$TAP_DIR"
TEST_RUNNER_TAPPER_DIR="$TAP_DIR" TEST_RUNNER_RUN_SECONDS=7000 timeout 7200 \
  xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "id=$UDID" >"$TMP/tapper.txt" 2>&1 &
TAPPER_PID=$!
for _ in $(seq 1 180); do [[ -f "$TAP_DIR/ready" ]] && break; sleep 1; done
[[ -f "$TAP_DIR/ready" ]] || { echo "tapper did not start"; tail -20 "$TMP/tapper.txt"; exit 1; }
tapper() {
  rm -f "$TAP_DIR/out"
  echo "$*" >"$TAP_DIR/cmd.tmp" && mv "$TAP_DIR/cmd.tmp" "$TAP_DIR/cmd"
  for _ in $(seq 1 120); do [[ -f "$TAP_DIR/out" ]] && break; sleep 0.25; done
  cat "$TAP_DIR/out" 2>/dev/null || echo "no answer"
}
restore() {
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLanguages 2>/dev/null || true
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLocale 2>/dev/null || true
  xcrun simctl ui "$UDID" content_size large 2>/dev/null || true
}
cleanup() {
  tapper orient portrait >/dev/null
  tapper quit >/dev/null; sleep 1; kill "$TAPPER_PID" 2>/dev/null
  restore
  [[ "$booted_here" == 1 ]] && xcrun simctl shutdown "$UDID" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

# ---- the app ----
lockf -t 3600 "$LOCK" timeout 900 flutter build ios --simulator --debug --dart-define=SPEECH_AUDIO="$AUDIO" >"$TMP/build.txt" 2>&1 || { echo "build failed"; tail -20 "$TMP/build.txt"; exit 1; }
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
echo "{\"phase\": $FIRST, \"last\": $LAST}" >"$DATA/Documents/ipad_test_phase"

setup() {
  tool/sim_permissions.sh grant "$UDID" >/dev/null
  restore
  case "$1" in
    2) xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLanguages -array es
       xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLocale es_US ;;
    3) xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large ;;
  esac
  echo "== set up for phase $1"
}

answer() { # n what...
  local n="$1"; shift
  local what="$*" ans="ok"
  case "$what" in
    "orient "*|"appdismiss "*) ans="$(tapper "$what")" ;;
    unlock)
      sleep 1.5
      for k in fingerTouch pearl; do xcrun simctl spawn "$UDID" notifyutil -p "com.apple.BiometricKit_Sim.$k.match"; done
      sleep 3
      for k in fingerTouch pearl; do xcrun simctl spawn "$UDID" notifyutil -p "com.apple.BiometricKit_Sim.$k.match"; done ;;
    *) ans="unknown" ;;
  esac
  echo "== ACT $n $what -> ${ans:0:200}"
  local dir; dir="$(cat "$TMP/actdir")"
  echo "$ans" >"$dir/act_$n.tmp" && mv "$dir/act_$n.tmp" "$dir/act_$n"
}

status=1
next=$FIRST
for run in $(seq 1 4); do
  echo "== run $run, phase $next"
  setup "$next"
  rm -f "$TMP/done" "$TMP/failed" "$TMP/next"
  lockf -t 3600 "$LOCK" timeout "$LIMIT" flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/ipad_test.dart \
    --dart-define=SPEECH_AUDIO="$AUDIO" --dart-define=LINK_SERVICE=http://127.0.0.1:9 --keep-app-running 2>&1 |
    while IFS= read -r line; do
      echo "$line"
      case "$line" in
        "flutter: ACT "*" -> "*) ;;
        "flutter: ACT "*) set -- ${line#flutter: ACT }; answer "$@" & ;;
        "flutter: ACTDIR "*) echo "${line#flutter: ACTDIR }" >"$TMP/actdir" ;;
        "flutter: NEXT "*) echo "${line#flutter: NEXT }" >"$TMP/next" ;;
        *"ALL DONE"*) touch "$TMP/done" ;;
        *"Some tests failed"*|*"[E]"*) touch "$TMP/failed" ;;
        *SIMSHOT*)
          name="${line##*SIMSHOT }"
          xcrun simctl io "$UDID" screenshot "$OUT_DIR/$name.png" >/dev/null 2>&1
          # simctl saves a landscape screen on its side: turned upright to look at
          [[ "$(basename "$name")" == l-* ]] && sips -r 270 "$OUT_DIR/$name.png" >/dev/null 2>&1 ;;
      esac
    done
  sleep 1 # (no bare `wait`: it would wait for the tapper too)
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  if [[ -f "$TMP/failed" ]]; then echo "== phase $next FAILED"; break; fi
  if [[ -f "$TMP/done" ]]; then status=0; echo "== ALL PHASES PASSED"; break; fi
  if [[ ! -f "$TMP/next" ]]; then echo "== phase $next ended without NEXT"; break; fi
  next="$(cat "$TMP/next")"
  sleep 2
done
exit $status
