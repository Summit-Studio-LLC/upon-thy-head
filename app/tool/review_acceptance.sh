#!/bin/bash
# The review page's acceptance run (integration_test/review_test.dart), filmed.
#
#   tool/review_acceptance.sh [simulator udid]
#
# Real speech through the real recogniser: built with SPEECH_AUDIO, so at Amen the recorder hands
# back integration_test/audio/en.m4a (and later es.m4a), which the phone's own recogniser writes.
# The test runs three times with --keep-app-running; between runs the app is killed with
# `xcrun simctl terminate`, so each part is a new process reading the store and the audio folder
# from disk. Permissions are granted before anything reaches Begin, and every run has a time limit,
# so a hang (a system alert) fails in minutes.
#
# Screenshots: ../design/sim/review/ (the simulator's own, on SIMSHOT lines).
# Film: ../design/sim/review/review.mp4, the three parts one after another.
# Text size: the test prints CONTENTSIZE <size> and this sets it with `simctl ui content_size`.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
AUDIO="$PWD/integration_test/audio"
OUT_DIR="$(cd .. && pwd)/design/sim/review"
LIMIT="${LIMIT:-600}" # seconds per part
export SIM_SHOTS=1
mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$UDID" content_size large || true
# start from part 1
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)"
[[ -n "$DATA" ]] && rm -f "$DATA/Documents/review_test_phase"
timeout 600 flutter build ios --simulator --debug --dart-define=SPEECH_AUDIO="$AUDIO" >/dev/null || { echo "build failed"; exit 1; }
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
tool/sim_permissions.sh grant "$UDID"

failed=0
for part in 1 2 3; do
  echo "== part $part"
  tool/sim_permissions.sh grant "$UDID" >/dev/null
  timeout "$LIMIT" flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/review_test.dart \
    --dart-define=SPEECH_AUDIO="$AUDIO" --keep-app-running 2>&1 |
    while IFS= read -r line; do
      echo "$line"
      case "$line" in
        *"REVIEW PHASE"*)
          xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$TMP/part$part.mp4" >/dev/null 2>&1 &
          echo $! > "$TMP/rec.pid" ;;
        *"PHASE "*" DONE"*)
          sleep 1; kill -INT "$(cat "$TMP/rec.pid")" 2>/dev/null; sleep 2 ;;
        *SIMSHOT*)
          name="${line##*SIMSHOT }"
          xcrun simctl io "$UDID" screenshot "$OUT_DIR/../$name.png" >/dev/null 2>&1 ;;
        *CONTENTSIZE*)
          xcrun simctl ui "$UDID" content_size "${line##*CONTENTSIZE }" ;;
      esac
    done
  # stop a recording left running by a failure
  [[ -f "$TMP/rec.pid" ]] && kill -INT "$(cat "$TMP/rec.pid")" 2>/dev/null
  rm -f "$TMP/rec.pid"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  echo "== terminated $BUNDLE"
  xcrun simctl ui "$UDID" content_size large || true
done

# the parts, one after another, phone-sized
ls "$TMP"/part*.mp4 >/dev/null 2>&1 && {
  for f in "$TMP"/part*.mp4; do echo "file '$f'"; done > "$TMP/list.txt"
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$TMP/list.txt" -vf "scale=804:-2,fps=30" -c:v libx264 -pix_fmt yuv420p -crf 22 -movflags +faststart "$OUT_DIR/review.mp4"
  ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT_DIR/review.mp4"
}
