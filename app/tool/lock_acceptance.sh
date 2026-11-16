#!/bin/bash
# The app lock, where blessings are given, and Settings (integration_test/lock_test.dart), on the
# simulator with real restarts.
#
#   tool/lock_acceptance.sh [simulator udid]
#
# The test runs once per phase with --keep-app-running; each phase is ended with
# `xcrun simctl terminate`, so the next is a new launch with the real lock. Before each phase this
# script sets the simulator up as the test's NEXT line asks:
#   1   the microphone, speech and location questions reset (case 1 answers them as a person
#       would, through the real prompts); Face ID enrolled; the simulator in Mexico City
#   2   the microphone and speech allowed, location reset (case 2 refuses it)
#   3-9 the microphone and speech allowed; location left as case 2 answered
#   10  Face ID enrolment removed; put back at the end. (A simulator still answers "passcode" then,
#       so case 8 replaces that answer with "none"; see the test.)
# While a phase runs, `ACT <n> <what>` lines are answered here and written to the app's tmp folder
# (which the test names on an ACTDIR line):
# Face ID by `notifyutil` (the Simulator's own Features > Face ID), the system's alerts, Home and the
# app switcher by tool/alerts (a UI test that runs alongside, reading commands from a folder).
#
# Every phase has a time limit, so a hang fails in minutes. Screenshots: ../design/sim/lock/.
# Film of cases 3 and 4: ../design/sim/lock/cases-3-4.mp4.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
OUT_DIR="$(cd .. && pwd)/design/sim/lock"
LIMIT="${LIMIT:-480}" # seconds per phase
TAP_DIR="${TMPDIR:-/tmp}/uth_tapper"
DD="${TMPDIR:-/tmp}/uth_tapper_dd"
mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"
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
  for _ in $(seq 1 120); do [[ -f "$TAP_DIR/out" ]] && break; sleep 0.25; done
  cat "$TAP_DIR/out" 2>/dev/null || echo "no answer"
}
cleanup() { tapper quit >/dev/null; sleep 1; kill "$TAPPER_PID" 2>/dev/null; }
trap cleanup EXIT

face() { xcrun simctl spawn "$UDID" notifyutil -p "com.apple.BiometricKit_Sim.pearl.$1"; }
enrol() { xcrun simctl spawn "$UDID" notifyutil -s com.apple.BiometricKit.enrollmentChanged "$1"; xcrun simctl spawn "$UDID" notifyutil -p com.apple.BiometricKit.enrollmentChanged; }

# ---- the app ----
timeout 600 flutter build ios --simulator --debug >/dev/null || { echo "build failed"; exit 1; }
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
START="${START:-1}" # START=n SHOTS=k: carry on from phase n, the screenshots numbered after k
if [[ "$START" == 1 ]]; then
  rm -f "$DATA/Documents/lock_test_phase"
  rm -f "$OUT_DIR"/[0-9][0-9]-*.png
else
  echo "{\"phase\": $START, \"shots\": ${SHOTS:-0}, \"acts\": 100}" >"$DATA/Documents/lock_test_phase"
fi

setup() { # before phase $1
  case "$1" in
    1) tool/sim_permissions.sh reset "$UDID" >/dev/null; enrol 1
       xcrun simctl location "$UDID" set 19.4326,-99.1332 ;;
    2) tool/sim_permissions.sh grant "$UDID" >/dev/null; xcrun simctl privacy "$UDID" reset location "$BUNDLE" ;;
    10) enrol 0 ;;
  esac
  if [[ "$1" -ge 3 ]]; then
    # the microphone and speech only; location stays as case 2 left it
    xcrun simctl privacy "$UDID" grant microphone "$BUNDLE"
    sqlite3 "$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/TCC/TCC.db" \
      "DELETE FROM access WHERE service = 'kTCCServiceSpeechRecognition' AND client = '$BUNDLE';
       INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags)
       VALUES ('kTCCServiceSpeechRecognition', '$BUNDLE', 0, 2, 2, 1, 0);"
    xcrun simctl spawn "$UDID" launchctl kill TERM system/com.apple.tccd 2>/dev/null || true
  fi
  echo "== set up for phase $1"
}

answer() { # ACT n what...
  local n="$1"; shift
  local what="$*" ans="ok"
  case "$what" in
    "face match") face match ;;
    "face nomatch") face nomatch ;;
    "tap "*|alert) ans="$(tapper "$what")" ;;
    "away "*)
      ans="$(tapper home)"; sleep "${what#away }"; ans="$ans; $(tapper open "$BUNDLE")" ;;
    "switcher "*)
      ans="$(tapper switcher)"; sleep 0.8
      xcrun simctl io "$UDID" screenshot "$OUT_DIR/../${what#switcher }.png" >/dev/null 2>&1
      sleep 0.5; ans="$ans; $(tapper open "$BUNDLE")" ;;
    *) ans="unknown" ;;
  esac
  echo "== ACT $n $what -> $ans"
  local dir; dir="$(cat "$TMP/actdir")" # the app's tmp folder; flutter drive moves the container
  echo "$ans" >"$dir/act_$n.tmp" && mv "$dir/act_$n.tmp" "$dir/act_$n"
}

status=1
next=$START
for run in $(seq 1 12); do
  echo "== run $run, phase $next"
  setup "$next"
  rm -f "$TMP/done" "$TMP/failed" "$TMP/next"
  timeout "$LIMIT" flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/lock_test.dart \
    --keep-app-running 2>&1 |
    while IFS= read -r line; do
      echo "$line"
      case "$line" in
        "flutter: ACT "*" -> "*) ;;
        "flutter: ACT "*) set -- ${line#flutter: ACT }; answer "$@" ;;
        "flutter: ACTDIR "*) echo "${line#flutter: ACTDIR }" >"$TMP/actdir" ;;
        "flutter: NEXT "*) echo "${line#flutter: NEXT }" >"$TMP/next" ;;
        *"FILM START"*)
          xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$TMP/film$run.mp4" >/dev/null 2>&1 &
          echo $! >"$TMP/rec.pid" ;;
        *"FILM END"*)
          sleep 1; kill -INT "$(cat "$TMP/rec.pid")" 2>/dev/null; rm -f "$TMP/rec.pid"; sleep 2 ;;
        *"ALL DONE"*) touch "$TMP/done" ;;
        *"Some tests failed"*|*"[E]"*) touch "$TMP/failed" ;;
        *SIMSHOT*)
          name="${line##*SIMSHOT }"
          xcrun simctl io "$UDID" screenshot "$OUT_DIR/../$name.png" >/dev/null 2>&1 ;;
      esac
    done
  [[ -f "$TMP/rec.pid" ]] && kill -INT "$(cat "$TMP/rec.pid")" 2>/dev/null
  rm -f "$TMP/rec.pid"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  if [[ -f "$TMP/failed" ]]; then echo "== phase $next FAILED"; break; fi
  if [[ -f "$TMP/done" ]]; then status=0; echo "== ALL PHASES PASSED"; break; fi
  if [[ ! -f "$TMP/next" ]]; then echo "== phase $next ended without NEXT"; break; fi
  next="$(cat "$TMP/next")"
  sleep 2
done
enrol 1

films=$(ls "$TMP"/film*.mp4 2>/dev/null | head -2)
if [[ -n "$films" ]]; then
  for f in $films; do echo "file '$f'"; done >"$TMP/list.txt"
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$TMP/list.txt" -vf "scale=804:-2,fps=30" -c:v libx264 -pix_fmt yuv420p -crf 22 -movflags +faststart "$OUT_DIR/cases-3-4.mp4"
  ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT_DIR/cases-3-4.mp4"
fi
exit $status
