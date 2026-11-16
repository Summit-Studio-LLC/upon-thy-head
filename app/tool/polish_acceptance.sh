#!/bin/bash
# Polish and the changes screen (integration_test/polish_test.dart), with real speech through the
# real recogniser and a real kill.
#
#   tool/polish_acceptance.sh [simulator udid]
#
# The test runs once per part with --keep-app-running. When the first prints KILL, this script
# kills the app's process with `kill -9` (SIGKILL: nothing is closed or saved on the way out); the
# second part is a new launch reading the store from disk. Permissions are granted before every
# part, and every part has a time limit.
#
# Screenshots: ../design/sim/polish/. Film of both parts: ../design/sim/polish/polish-run.mp4.
# Side by side with the prototype: ../design/sim/polish/17-side-by-side.png.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
AUDIO="$PWD/integration_test/audio"
OUT_DIR="$(cd .. && pwd)/design/sim/polish"
LIMIT="${LIMIT:-420}" # seconds per phase
mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$UDID" content_size large || true
# start from phase 1
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)"
[[ -n "$DATA" ]] && rm -f "$DATA/Documents/polish_test_phase"
timeout 600 flutter build ios --simulator --debug --dart-define=SPEECH_AUDIO="$AUDIO" >/dev/null || { echo "build failed"; exit 1; }
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
tool/sim_permissions.sh grant "$UDID"

app_pid() { pgrep -f "$UDID/data/Containers/Bundle/Application/.*/Runner.app/Runner" | head -1; }
now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

status=1
for run in 1 2 3; do
  echo "== run $run"
  tool/sim_permissions.sh grant "$UDID" >/dev/null
  rm -f "$TMP/killed" "$TMP/done" "$TMP/failed"
  timeout "$LIMIT" flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/polish_test.dart \
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

# both parts, one after another, phone-sized
films=$(ls "$TMP"/film*.mp4 2>/dev/null | head -2)
if [[ -n "$films" ]]; then
  for f in $films; do echo "file '$f'"; done > "$TMP/list.txt"
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$TMP/list.txt" -vf "scale=804:-2,fps=30" -c:v libx264 -pix_fmt yuv420p -crf 22 -movflags +faststart "$OUT_DIR/polish-run.mp4"
  ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT_DIR/polish-run.mp4"
fi
# the sample's changes screen beside the prototype's, at the same scale (3 pixels to the point),
# tops aligned: the phone is 402 x 874 points, the prototype 390 x 844
PROTO="$(cd .. && pwd)/design/prototype/shots/05-review-changes.png"
if [[ -f "$OUT_DIR/16-sample-last-change.png" ]]; then
  ffmpeg -y -loglevel error -i "$PROTO" -i "$OUT_DIR/16-sample-last-change.png" \
    -filter_complex "[0]pad=iw+40:2622:0:0:color=0x333333[a];[a][1]hstack" "$OUT_DIR/17-side-by-side.png"
fi
exit $status
