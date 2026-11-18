#!/bin/bash
# Recovery of recordings cut short by the app being killed (integration_test/recovery_test.dart).
#
#   tool/recovery_acceptance.sh [simulator udid]
#
# The test runs once per phase with --keep-app-running. When a phase prints KILL, this script kills
# the app's process with `kill -9`: SIGKILL, which the app cannot catch, so nothing is closed or
# saved on the way out, as when iOS ends a suspended app or it crashes. The kill is real, never
# simulated. A phase that ends without KILL is ended with `xcrun simctl terminate`. Each phase is a
# new process reading the store and the audio folder from disk.
#
# Built with SPEECH_AUDIO (case 4 feeds the English test passage in at Amen). Permissions are
# granted before every phase, and every phase has a time limit, so a hang fails in minutes.
#
# Screenshots: ../design/sim/recovery/. Film of case 1: ../design/sim/recovery/case1.mp4.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
AUDIO="$PWD/integration_test/audio"
OUT_DIR="$(cd .. && pwd)/design/sim/recovery"
LIMIT="${LIMIT:-420}" # seconds per phase
mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$UDID" content_size large || true
# start from an empty app: another script's leftovers (a remembered Spanish recording language, for
# which the simulator has no speech engine) once failed the last case here
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
# start from phase 1
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)"
[[ -n "$DATA" ]] && rm -f "$DATA/Documents/recovery_test_phase"
timeout 600 flutter build ios --simulator --debug --dart-define=SPEECH_AUDIO="$AUDIO" >/dev/null || { echo "build failed"; exit 1; }
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
tool/sim_permissions.sh grant "$UDID"

app_pid() { pgrep -f "$UDID/data/Containers/Bundle/Application/.*/Runner.app/Runner" | head -1; }
now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

status=1
for run in 1 2 3 4 5 6 7 8 9; do
  echo "== run $run"
  tool/sim_permissions.sh grant "$UDID" >/dev/null
  rm -f "$TMP/killed" "$TMP/done" "$TMP/failed"
  timeout "$LIMIT" flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/recovery_test.dart \
    --dart-define=SPEECH_AUDIO="$AUDIO" --keep-app-running 2>&1 |
    while IFS= read -r line; do
      echo "$line"
      case "$line" in
        *"FILM START"*)
          xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$TMP/film$run.mp4" >/dev/null 2>&1 &
          echo $! > "$TMP/rec.pid" ;;
        *"FILM END"*)
          sleep 1; kill -INT "$(cat "$TMP/rec.pid")" 2>/dev/null; rm -f "$TMP/rec.pid"; sleep 2 ;;
        "flutter: KILL "*)
          pid="$(app_pid)"
          if [[ -z "$pid" ]]; then echo "== KILL: no app process found"; touch "$TMP/failed"; continue; fi
          kill -9 "$pid"
          at="$(now_ms)"
          sleep 0.5
          if kill -0 "$pid" 2>/dev/null; then echo "== KILL: process $pid still alive"; touch "$TMP/failed"; fi
          asked="$(echo "$line" | awk '{print $3}')"
          echo "== KILLED pid $pid with SIGKILL at $at ms ($line), $(( at - ${asked:-$at} )) ms after the test asked"
          touch "$TMP/killed"
          [[ -f "$TMP/rec.pid" ]] && { sleep 1; kill -INT "$(cat "$TMP/rec.pid")" 2>/dev/null; rm -f "$TMP/rec.pid"; sleep 2; }
          # the driver has lost its app; do not wait for it to notice
          drivers="$(pgrep -f "flutter_tools.snapshot drive -d $UDID" | tr '\n' ' ')"
          ( sleep 5; kill $drivers ) >/dev/null 2>&1 & ;;
        *"ALL DONE"*) touch "$TMP/done" ;;
        *"Some tests failed"*|*"[E]"*) touch "$TMP/failed" ;;
        *SIMSHOT*)
          name="${line##*SIMSHOT }"
          xcrun simctl io "$UDID" screenshot "$OUT_DIR/../$name.png" >/dev/null 2>&1 ;;
      esac
    done
  [[ -f "$TMP/rec.pid" ]] && kill -INT "$(cat "$TMP/rec.pid")" 2>/dev/null
  rm -f "$TMP/rec.pid"
  if [[ -f "$TMP/failed" ]]; then echo "== run $run FAILED"; break; fi
  if [[ ! -f "$TMP/killed" ]]; then
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    echo "== terminated $BUNDLE"
  fi
  if [[ -f "$TMP/done" ]]; then status=0; echo "== ALL PHASES PASSED"; break; fi
  sleep 2
done

# case 1, the recording and the relaunch, one after another, phone-sized
films=$(ls "$TMP"/film*.mp4 2>/dev/null | head -2)
if [[ -n "$films" ]]; then
  for f in $films; do echo "file '$f'"; done > "$TMP/list.txt"
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$TMP/list.txt" -vf "scale=804:-2,fps=30" -c:v libx264 -pix_fmt yuv420p -crf 22 -movflags +faststart "$OUT_DIR/case1.mp4"
  ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT_DIR/case1.mp4"
fi
exit $status
