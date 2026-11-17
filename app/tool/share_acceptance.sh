#!/bin/bash
# Sharing as text and as a PDF (integration_test/share_test.dart), on the simulator with the real
# system share sheet and real restarts.
#
#   tool/share_acceptance.sh [simulator udid]
#
# The test runs once per phase with --keep-app-running; each phase is a new launch:
#   1  English, US region: the icon; text copied from the sheet; four PDFs; the switcher and the lock
#      with the sheet up; then a PDF left prepared, and the app killed here with `kill -9`
#   2  English: the next launch has removed the file
#   3  Spanish (the app's language, as iOS Settings > the app > Language sets it)
#   4  English with a British region: A4
# `ACT <n> <what>` lines are answered here (see the test), the share sheet's buttons and the
# switcher by tool/alerts (a UI test that runs alongside). The PDFs the sheet is given are copied to
# ../design/sim/share/<en|es|a4>/ and checked by tool/pdf_check.swift, which also renders each page.
# Every phase has a time limit.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
OUT_DIR="$(cd .. && pwd)/design/sim/share"
LIMIT="${LIMIT:-900}" # seconds per phase
TAP_DIR="${TMPDIR:-/tmp}/uth_tapper"
DD="${TMPDIR:-/tmp}/uth_tapper_dd"
mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"

state="$(xcrun simctl list devices | grep "$UDID" || true)"
[[ "$state" == *Booted* ]] || { echo "booting the simulator"; xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID" -b >/dev/null; }
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$UDID" content_size large || true

timeout 300 swiftc -O -o "$TMP/pdf_check" tool/pdf_check.swift 2>"$TMP/swiftc.txt" || { echo "pdf_check build failed"; cat "$TMP/swiftc.txt"; exit 1; }

# ---- the alert tapper ----
timeout 600 xcodebuild build-for-testing -project tool/alerts/Tapper.xcodeproj -scheme TapperUITests \
  -destination "id=$UDID" -derivedDataPath "$DD" >"$TMP/tapper_build.txt" 2>&1 || { echo "tapper build failed"; tail -20 "$TMP/tapper_build.txt"; exit 1; }
XCTESTRUN="$(ls "$DD"/Build/Products/*.xctestrun | head -1)"
rm -rf "$TAP_DIR"; mkdir -p "$TAP_DIR"
TEST_RUNNER_TAPPER_DIR="$TAP_DIR" TEST_RUNNER_RUN_SECONDS=5400 timeout 5600 \
  xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "id=$UDID" >"$TMP/tapper.txt" 2>&1 &
TAPPER_PID=$!
for _ in $(seq 1 120); do [[ -f "$TAP_DIR/ready" ]] && break; sleep 1; done
[[ -f "$TAP_DIR/ready" ]] || { echo "tapper did not start"; tail -20 "$TMP/tapper.txt"; exit 1; }
tapper() { # one command; prints its answer
  rm -f "$TAP_DIR/out"
  echo "$*" >"$TAP_DIR/cmd.tmp" && mv "$TAP_DIR/cmd.tmp" "$TAP_DIR/cmd"
  for _ in $(seq 1 120); do [[ -f "$TAP_DIR/out" ]] && break; sleep 0.25; done
  cat "$TAP_DIR/out" 2>/dev/null || echo "no answer"
}
restore() {
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLanguages 2>/dev/null || true
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLocale 2>/dev/null || true
}
cleanup() { tapper quit >/dev/null; sleep 1; kill "$TAPPER_PID" 2>/dev/null; restore; }
trap cleanup EXIT

face() { xcrun simctl spawn "$UDID" notifyutil -p "com.apple.BiometricKit_Sim.pearl.$1"; }
enrol() { xcrun simctl spawn "$UDID" notifyutil -s com.apple.BiometricKit.enrollmentChanged "$1"; xcrun simctl spawn "$UDID" notifyutil -p com.apple.BiometricKit.enrollmentChanged; }
enrol 1 # the lock case answers Face ID with the enrolled face
app_pid() { pgrep -f "$UDID/data/Containers/Bundle/Application/.*/Runner.app/Runner" | head -1; }

# ---- the app ----
timeout 600 flutter build ios --simulator --debug >/dev/null || { echo "build failed"; exit 1; }
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
rm -f "$DATA/Documents/share_test_phase"
rm -rf "$OUT_DIR"/[0-9][0-9]-*.png "$OUT_DIR"/en "$OUT_DIR"/es "$OUT_DIR"/a4 "$OUT_DIR"/kill.txt

setup() { # before phase $1
  tool/sim_permissions.sh grant "$UDID" >/dev/null
  restore
  case "$1" in
    3) xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLanguages -array es
       xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLocale es_US ;;
    4) xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLanguages -array en
       xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLocale en_GB ;;
  esac
  echo "== set up for phase $1"
}

answer() { # ACT n what...
  local n="$1"; shift
  local what="$*" ans="ok"
  case "$what" in
    "face match") face match ;;
    "apptap "*|"appdismiss "*) ans="$(tapper "$what")" ;;
    pbclear) printf '' | xcrun simctl pbcopy "$UDID"; ans=ok ;;
    pasteboard) ans="$(xcrun simctl pbpaste "$UDID" | base64)" ;;
    "keep "*)
      set -- ${what#keep }
      local pdf json dir stem
      pdf="$(echo "$1" | base64 -d)"; json="$(echo "$2" | base64 -d)"; dir="$OUT_DIR/$3"
      mkdir -p "$dir"
      cp "$pdf" "$dir/" && cp "$json" "$dir/$(basename "${pdf%.pdf}").expected.json"
      stem="$(basename "${pdf%.pdf}")"
      timeout 120 "$TMP/pdf_check" "$dir/$(basename "$pdf")" "$dir/$stem.expected.json" "$dir" >"$dir/$stem.check.txt" 2>&1
      if grep -q "PDF CHECK PASSED" "$dir/$stem.check.txt"; then ans="PASSED $(grep -c '^ok' "$dir/$stem.check.txt") checks, $(grep '^pages' "$dir/$stem.check.txt")"
      else ans="FAILED $(grep -E '^FAIL|^     ' "$dir/$stem.check.txt" | head -8 | tr '\n' ';')"; fi ;;
    "away "*)
      ans="$(tapper home)"; sleep "${what#away }"; ans="$ans; $(tapper open "$BUNDLE")" ;;
    "switcher "*)
      ans="$(tapper switcher)"; sleep 0.8
      xcrun simctl io "$UDID" screenshot "$OUT_DIR/../${what#switcher }.png" >/dev/null 2>&1
      sleep 0.5; ans="$ans; $(tapper open "$BUNDLE")" ;;
    *) ans="unknown" ;;
  esac
  echo "== ACT $n $what -> ${ans:0:300}"
  local dir; dir="$(cat "$TMP/actdir")"
  echo "$ans" >"$dir/act_$n.tmp" && mv "$dir/act_$n.tmp" "$dir/act_$n"
}

status=1
next=1
for run in $(seq 1 8); do
  echo "== run $run, phase $next"
  setup "$next"
  rm -f "$TMP/done" "$TMP/failed" "$TMP/next" "$TMP/kill"
  timeout "$LIMIT" flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/share_test.dart --dart-define=LINK_SERVICE=http://127.0.0.1:9 \
    --keep-app-running 2>&1 |
    while IFS= read -r line; do
      echo "$line"
      case "$line" in
        "flutter: ACT "*" -> "*) ;;
        "flutter: ACT "*) set -- ${line#flutter: ACT }; answer "$@" ;;
        "flutter: ACTDIR "*) echo "${line#flutter: ACTDIR }" >"$TMP/actdir" ;;
        "flutter: NEXT "*) echo "${line#flutter: NEXT }" >"$TMP/next" ;;
        "flutter: KILL "*) echo "${line#flutter: KILL }" | base64 -d >"$TMP/kill" ;;
        *"ALL DONE"*) touch "$TMP/done" ;;
        *"Some tests failed"*|*"[E]"*) touch "$TMP/failed" ;;
        *SIMSHOT*)
          name="${line##*SIMSHOT }"
          xcrun simctl io "$UDID" screenshot "$OUT_DIR/../$name.png" >/dev/null 2>&1 ;;
      esac
    done
  if [[ -f "$TMP/kill" ]]; then
    dir="$(cat "$TMP/kill")"
    { echo "before kill -9, with the sheet up:"; ls -la "$dir"; } | tee "$OUT_DIR/kill.txt"
    pid="$(app_pid)"; [[ -n "$pid" ]] && kill -9 "$pid"; sleep 2
    { echo "after kill -9, before relaunch:"; ls -la "$dir" 2>&1; } | tee -a "$OUT_DIR/kill.txt"
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  if [[ -f "$TMP/failed" ]]; then echo "== phase $next FAILED"; break; fi
  if [[ -f "$TMP/done" ]]; then status=0; echo "== ALL PHASES PASSED"; break; fi
  if [[ ! -f "$TMP/next" ]]; then echo "== phase $next ended without NEXT"; break; fi
  next="$(cat "$TMP/next")"
  sleep 2
done
exit $status
