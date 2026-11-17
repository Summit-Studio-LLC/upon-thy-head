#!/bin/bash
# Sending and receiving a blessing as a `.blessing` file (integration_test/file_test.dart), on the
# simulator, with the file reaching the app the way iOS delivers it.
#
#   tool/file_acceptance.sh [simulator udid]
#
# The test is built into the app (flutter build --target) and runs at every launch, so a phase can
# begin with iOS launching the app for a file, which `flutter drive` cannot do. It talks to this
# script through files in the app's container (see the test's header). Phases:
#   1  launched here: share as a file, the files saved out; the blessings deleted
#   2  launched by a tap on the saved file in the Files app (tool/alerts), filmed to the reading page;
#      then the same file, an edited copy, the background, the lock, refusals, a recording
#   3  Spanish, launched by `simctl openurl` with a file
# Screenshots and the film land in ../design/sim/file/, the files the share sheet held in
# ../design/sim/file/files/. Every phase has a time limit.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
OUT_DIR="$(cd .. && pwd)/design/sim/file"
LIMIT="${LIMIT:-900}" # seconds per phase
TAP_DIR="${TMPDIR:-/tmp}/uth_tapper"
DD="${TMPDIR:-/tmp}/uth_tapper_dd"
TMP="$(mktemp -d)"
FIX="$TMP/files" # the files, on the Mac, as another phone would send them
mkdir -p "$OUT_DIR/files" "$FIX"
rm -f "$OUT_DIR"/[0-9][0-9]-*.png "$OUT_DIR"/files/*.blessing "$OUT_DIR"/step2-*.mov

state="$(xcrun simctl list devices | grep "$UDID" || true)"
[[ "$state" == *Booted* ]] || { echo "booting the simulator"; xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID" -b >/dev/null; }
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$UDID" content_size large || true

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
  for _ in $(seq 1 "${TAP_WAIT:-240}"); do [[ -f "$TAP_DIR/out" ]] && break; sleep 0.25; done
  cat "$TAP_DIR/out" 2>/dev/null || echo "no answer"
}
restore() {
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLanguages 2>/dev/null || true
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLocale 2>/dev/null || true
  xcrun simctl ui "$UDID" content_size large 2>/dev/null || true
}
# Start from the phone's own language: an earlier run (the Spanish one) may have left the app in Spanish.
restore
FILM_PID=""
LOG_PID=""
cleanup() {
  tapper quit >/dev/null; sleep 1; kill "$TAPPER_PID" 2>/dev/null
  [[ -n "$FILM_PID" ]] && kill -INT "$FILM_PID" 2>/dev/null
  [[ -n "$LOG_PID" ]] && kill "$LOG_PID" 2>/dev/null
  restore
}
trap cleanup EXIT

app_pid() { pgrep -f "$UDID/data/Containers/Bundle/Application/.*/Runner.app/Runner" | head -1; }
face() { xcrun simctl spawn "$UDID" notifyutil -p "com.apple.BiometricKit_Sim.pearl.$1"; }
enrol() { xcrun simctl spawn "$UDID" notifyutil -s com.apple.BiometricKit.enrollmentChanged "$1"; xcrun simctl spawn "$UDID" notifyutil -p com.apple.BiometricKit.enrollmentChanged; }
enrol 1
urlfor() { python3 -c 'import sys, urllib.parse; print("file://" + urllib.parse.quote(sys.argv[1]))' "$1"; }
openfile() { xcrun simctl openurl "$UDID" "$(urlfor "$FIX/$1")"; }

# the Files app's "On My iPhone" folder
LOCAL=""
for meta in "$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Shared/AppGroup"/*/.com.apple.mobile_container_manager.metadata.plist; do
  if [[ "$(plutil -p "$meta" 2>/dev/null)" == *'"group.com.apple.FileProvider.LocalStorage"'* ]]; then LOCAL="$(dirname "$meta")/File Provider Storage"; fi
done
[[ -n "$LOCAL" ]] || { echo "no On My iPhone folder; open the Files app once on this simulator"; exit 1; }
mkdir -p "$LOCAL"
rm -f "$LOCAL"/*.blessing

# ---- the app, with the test inside ----
timeout 600 flutter build ios --simulator --debug --target=integration_test/file_test.dart --dart-define=LINK_SERVICE=http://127.0.0.1:9 >"$TMP/build.txt" 2>&1 || { echo "build failed"; tail -20 "$TMP/build.txt"; exit 1; }
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)" # it moves on each install
rm -rf "$DATA/Documents/file_test_phase" "$DATA/Documents/file_test_status" "$DATA/Documents/file_test_log.txt" "$DATA/tmp/fileacts"
mkdir -p "$DATA/tmp/fileacts"
touch "$DATA/Documents/file_test_log.txt"
tail -n 0 -F "$DATA/Documents/file_test_log.txt" 2>/dev/null | sed -u 's/^/   test: /' &
LOG_PID=$!
ACTS="$DATA/tmp/fileacts"
tool/sim_permissions.sh grant "$UDID" >/dev/null

answer() { # n what...
  local n="$1"; shift
  local what="$*" ans="ok"
  case "$what" in
    "face match") face match ;;
    "appdismiss "*) ans="$(tapper "$what")" ;;
    "shot "*) xcrun simctl io "$UDID" screenshot "$OUT_DIR/${what#shot }.png" >/dev/null 2>&1 || ans="screenshot failed" ;;
    "save "*)
      local f; f="$(echo "${what#save }" | base64 -d)"
      cp "$f" "$OUT_DIR/files/" && cp "$f" "$FIX/" || ans="copy failed"
      [[ "$(basename "$f")" == "Comfort before surgery, March 3, 2026.blessing" ]] && cp "$f" "$LOCAL/"
      ans="$ans $(stat -f %z "$f") bytes" ;;
    "fixtures "*)
      local d; d="$(echo "${what#fixtures }" | base64 -d)"
      cp "$d"/*.blessing "$FIX/" || ans="copy failed"; ans="$ans $(ls "$d" | wc -l | tr -d ' ') files" ;;
    "open "*) openfile "${what#open }" || ans="openurl failed" ;;
    "bg "*)
      set -- ${what#bg }
      local s="$1"; local name="${what#bg $1 }"
      ans="$(tapper home)"; sleep "$s"; openfile "$name" || ans="$ans; openurl failed" ;;
    "film stop")
      if [[ -n "$FILM_PID" ]]; then kill -INT "$FILM_PID"; wait "$FILM_PID" 2>/dev/null; FILM_PID=""; fi ;;
    "textsize "*) xcrun simctl ui "$UDID" content_size "${what#textsize }" || ans="failed" ;;
    *) ans="unknown" ;;
  esac
  echo "== ACT $n $what -> ${ans:0:200}" >&2
  echo "$ans" >"$ACTS/act_$n.tmp" && mv "$ACTS/act_$n.tmp" "$ACTS/act_$n"
}

serve() { # answer the test until it says how the phase ended; prints that
  local end=$((SECONDS + LIMIT)) st=""
  rm -f "$DATA/Documents/file_test_status"
  while ((SECONDS < end)); do
    for ask in "$ACTS"/ask_*; do
      [[ -f "$ask" ]] || continue
      local n="${ask##*_}"
      [[ "$n" == *.tmp ]] && continue
      local what; what="$(cat "$ask")"; rm -f "$ask"
      answer "$n" "$what"
    done
    if [[ -f "$DATA/Documents/file_test_status" ]]; then st="$(cat "$DATA/Documents/file_test_status")"; break; fi
    sleep 0.2
  done
  echo "${st:-timed out}"
}

status=1
for phase in 1 2 3; do
  echo "== phase $phase"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 2
  case "$phase" in
    1) xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null ;;
    2) # filmed: from the tap in Files to the reading page
       xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT_DIR/step2-files-tap.mov" >/dev/null 2>&1 &
       FILM_PID=$!
       sleep 2
       # Files from a fresh start, so it is on its own screens and not a stale view; then make sure
       # the tap really launched the app, or tap again
       for try in 1 2 3; do
         xcrun simctl terminate "$UDID" com.apple.DocumentsApp 2>/dev/null || true; sleep 2
         got="$(TAP_WAIT=600 tapper files Comfort)"; echo "== files ($try): $got"
         for _ in $(seq 1 30); do [[ -n "$(app_pid)" ]] && break; sleep 1; done
         [[ -n "$(app_pid)" ]] && break
       done ;;
    3) xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLanguages -array es
       xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLocale es_US
       openfile "Para Sofía.blessing" ;;
  esac
  got="$(serve)"
  echo "== phase $phase: $got"
  case "$got" in
    "next "*) ;;
    done) status=0; echo "== ALL PHASES PASSED"; break ;;
    *) echo "== phase $phase FAILED"; break ;;
  esac
done
[[ -n "$FILM_PID" ]] && { kill -INT "$FILM_PID" 2>/dev/null; wait "$FILM_PID" 2>/dev/null; FILM_PID=""; }
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
grep '^RESULTS' "$DATA/Documents/file_test_log.txt" | tail -1
exit $status
