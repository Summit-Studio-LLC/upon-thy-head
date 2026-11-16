#!/bin/bash
# The core flow with the app in Spanish (integration_test/spanish_test.dart), on the simulator with
# real restarts, a real kill, real Face ID and the system's own questions.
#
#   tool/spanish_acceptance.sh [simulator udid]          Spanish, normal text size then the first
#                                                         accessibility size
#   UI_LANG=en SETS=normal tool/spanish_acceptance.sh     the same screens in English (the walk then
#                                                         fails on any Spanish)
#
# The app's own language is set as iOS Settings > Upon Thy Head > Language sets it (AppleLanguages
# in the app's preferences), the same as launching with `-AppleLanguages "(es)"`; the simulator's own
# language is left alone, so Apple's parts of the system questions (titles, buttons) stay English
# here while the app's lines in them are Spanish. On a phone set to Spanish all of it is Spanish.
#
# Each set runs the test twice with --keep-app-running: phase 1 ends with KILL (this script kills
# the app with `kill -9`), phase 2 is the next launch. Before the first set the microphone, speech
# and location questions are reset, so phase 1 answers them as a person would (tool/alerts taps
# them). Every phase has a time limit.
#
# Screenshots: ../design/sim/spanish/ (and ax/). Film: ../design/sim/spanish/flow.mp4.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
UI_LANG="${UI_LANG:-es}"
SETS="${SETS:-normal ax}"
AUDIO="$PWD/integration_test/audio"
NAME="spanish"; [[ "$UI_LANG" == en ]] && NAME="english-check"
OUT_DIR="$(cd .. && pwd)/design/sim/$NAME"
LIMIT="${LIMIT:-840}" # seconds per phase
TAP_DIR="${TMPDIR:-/tmp}/uth_tapper"
DD="${TMPDIR:-/tmp}/uth_tapper_dd"
TMP="$(mktemp -d)"
EXTRA="$TMP/extra"
mkdir -p "$OUT_DIR" "$EXTRA"
# a silent recording and a broken one, for the after-Amen screen's other states
ffmpeg -loglevel error -y -f lavfi -i anullsrc=r=32000:cl=mono -t 14 -c:a aac -b:a 24k "$EXTRA/silence.m4a"
head -c 40000 /dev/urandom >"$EXTRA/broken.m4a"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true

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
tapper() {
  rm -f "$TAP_DIR/out"
  echo "$*" >"$TAP_DIR/cmd.tmp" && mv "$TAP_DIR/cmd.tmp" "$TAP_DIR/cmd"
  for _ in $(seq 1 120); do [[ -f "$TAP_DIR/out" ]] && break; sleep 0.25; done
  cat "$TAP_DIR/out" 2>/dev/null || echo "no answer"
}
cleanup() { tapper quit >/dev/null; sleep 1; kill "$TAPPER_PID" 2>/dev/null; xcrun simctl ui "$UDID" content_size large || true; }
trap cleanup EXIT
# a question left on screen by an earlier run that stopped part-way: answer it (the permissions are
# reset below anyway)
for _ in 1 2 3; do
  left="$(tapper alert)"; [[ "$left" == none ]] && break
  echo "== an earlier question was still up: $left"
  tapper tap "Don't Allow" >/dev/null || tapper tap OK >/dev/null
  sleep 1
done
face() { xcrun simctl spawn "$UDID" notifyutil -p "com.apple.BiometricKit_Sim.pearl.$1"; }
xcrun simctl spawn "$UDID" notifyutil -s com.apple.BiometricKit.enrollmentChanged 1
xcrun simctl spawn "$UDID" notifyutil -p com.apple.BiometricKit.enrollmentChanged
app_pid() { pgrep -f "$UDID/data/Containers/Bundle/Application/.*/Runner.app/Runner" | head -1; }

# ---- the app, in the language asked for ----
DEFINES=(--dart-define=SPEECH_AUDIO="$AUDIO" --dart-define=EXTRA_AUDIO="$EXTRA" --dart-define=UI_LANG="$UI_LANG")
timeout 600 flutter build ios --simulator --debug "${DEFINES[@]}" >/dev/null || { echo "build failed"; exit 1; }
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
if [[ "$UI_LANG" == es ]]; then
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLanguages -array es
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLocale es_US
else
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLanguages 2>/dev/null || true
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLocale 2>/dev/null || true
fi
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
xcrun simctl location "$UDID" set 19.4326,-99.1332

answer() { # ACT n what...
  local n="$1"; shift
  local what="$*" ans="ok"
  case "$what" in
    "face match") face match ;;
    "face nomatch") face nomatch ;;
    "tap "*|alert) ans="$(tapper "$what")" ;;
    *) ans="unknown" ;;
  esac
  echo "== ACT $n $what -> $ans"
  local dir; dir="$(cat "$TMP/actdir")"
  echo "$ans" >"$dir/act_$n.tmp" && mv "$dir/act_$n.tmp" "$dir/act_$n"
}

status=0
first=1
for set in $SETS; do
  if [[ "$set" == ax ]]; then sub="$NAME/ax"; size=accessibility-medium; else sub="$NAME"; size=large; fi
  xcrun simctl ui "$UDID" content_size "$size"
  rm -f "$(cd .. && pwd)/design/sim/$sub"/[0-9][0-9]-*.png
  mkdir -p "$(cd .. && pwd)/design/sim/$sub"
  if [[ $first == 1 ]]; then tool/sim_permissions.sh reset "$UDID" >/dev/null; prompts=true; else tool/sim_permissions.sh grant "$UDID" >/dev/null; prompts=false; fi
  first=0
  # the app's data folder moves when the app is installed again, so look it up for each set
  DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
  echo "{\"phase\": 1, \"dir\": \"$sub\", \"prompts\": $prompts}" >"$DATA/Documents/spanish_test_phase"
  ok=0
  for phase in 1 2; do
    echo "== $set, phase $phase (text size $size)"
    rm -f "$TMP/done" "$TMP/failed" "$TMP/next" "$TMP/killed"
    timeout "$LIMIT" flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/spanish_test.dart \
      "${DEFINES[@]}" --keep-app-running 2>&1 |
      while IFS= read -r line; do
        echo "$line"
        case "$line" in
          "flutter: ACT "*" -> "*) ;;
          "flutter: ACT "*) set -- ${line#flutter: ACT }; answer "$@" ;;
          "flutter: ACTDIR "*) echo "${line#flutter: ACTDIR }" >"$TMP/actdir" ;;
          "flutter: NEXT "*) echo "${line#flutter: NEXT }" >"$TMP/next" ;;
          *"FILM START"*)
            if [[ "$set" == normal ]]; then
              xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$TMP/film.mp4" >/dev/null 2>&1 &
              echo $! >"$TMP/rec.pid"
            fi ;;
          *"FILM END"*)
            [[ -f "$TMP/rec.pid" ]] && { sleep 1; kill -INT "$(cat "$TMP/rec.pid")" 2>/dev/null; rm -f "$TMP/rec.pid"; sleep 2; } ;;
          "flutter: KILL"*)
            pid="$(app_pid)"
            if [[ -z "$pid" ]]; then echo "== KILL: no app process found"; touch "$TMP/failed"; continue; fi
            kill -9 "$pid"; sleep 0.5
            echo "== KILLED pid $pid with SIGKILL"
            touch "$TMP/killed"
            drivers="$(pgrep -f "flutter_tools.snapshot drive -d $UDID" | tr '\n' ' ')"
            ( sleep 5; kill $drivers ) >/dev/null 2>&1 & ;;
          *"ALL DONE"*) touch "$TMP/done" ;;
          *"Some tests failed"*|*"[E]"*) touch "$TMP/failed" ;;
          *SIMSHOT*)
            name="${line##*SIMSHOT }"
            xcrun simctl io "$UDID" screenshot "$(cd .. && pwd)/design/sim/$name.png" >/dev/null 2>&1 ;;
        esac
      done
    [[ -f "$TMP/rec.pid" ]] && { kill -INT "$(cat "$TMP/rec.pid")" 2>/dev/null; rm -f "$TMP/rec.pid"; }
    if [[ -f "$TMP/failed" ]]; then echo "== $set phase $phase FAILED"; break; fi
    if [[ $phase == 1 && ! -f "$TMP/killed" ]]; then echo "== $set phase 1 ended without the kill"; break; fi
    if [[ $phase == 2 ]]; then
      xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
      [[ -f "$TMP/done" ]] && ok=1
    fi
    sleep 2
  done
  if [[ $ok == 1 ]]; then echo "== $set PASSED"; else echo "== $set FAILED"; status=1; break; fi
done

if [[ -f "$TMP/film.mp4" ]]; then
  ffmpeg -y -loglevel error -i "$TMP/film.mp4" -vf "scale=804:-2,fps=30" -c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart "$OUT_DIR/flow.mp4"
  echo "== film $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT_DIR/flow.mp4") s"
fi
exit $status
