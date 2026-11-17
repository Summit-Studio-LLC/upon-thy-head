#!/bin/bash
# Android's words, unattended (docs/android-plan.md tasks 8 to 10, acceptance 1, 3, 4 and 5): serves
# the speech model from this Mac (tool/model_server.py, 127.0.0.1 only), builds a debug app that
# downloads it from there, boots the emulator with its audio off, runs tool/android_words.py, and
# shuts the emulator and the server down. About 15 minutes.
#
#   tool/android_words.sh MODEL_FILE [avd] [--only 1,3,5,4]      default Pixel_10_Pro
#
# MODEL_FILE is ggml-base-q5_1.bin (59,707,625 bytes, the SHA-256 in lib/record/words_model.dart);
# the app refuses any other. Results and screenshots land in build/android_words/<avd>/, with
# summary.json and the server's request log.
set -uo pipefail
cd "$(dirname "$0")/.."
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"
MODEL=${1:?the model file: ggml-base-q5_1.bin}
shift
AVD=Pixel_10_Pro
[[ $# -gt 0 && "$1" != --* ]] && { AVD=$1; shift; }
WORK=build/android_words
OUT=$WORK/$AVD
PORT=4330
mkdir -p "$OUT"

limit() { # limit SECONDS command...: stopped if it runs longer
  local s=$1; shift
  perl -e 'alarm shift; exec @ARGV or die "cannot run $ARGV[0]"' "$s" "$@"
  local code=$?
  [[ $code == 142 ]] && echo "TIMED OUT after ${s}s: $*"
  return $code
}

started=0 server=
cleanup() {
  [[ -n "$server" ]] && kill "$server" 2>/dev/null && echo "== model server stopped"
  if [[ $started == 1 ]]; then
    adb -s "$DEV" shell settings delete global sys_storage_threshold_max_bytes >/dev/null 2>&1
    adb -s "$DEV" shell 'cmd connectivity airplane-mode disable; svc wifi enable; svc data enable' >/dev/null 2>&1
    adb -s "$DEV" emu kill >/dev/null 2>&1
    for _ in $(seq 60); do adb devices | grep -q "^$DEV" || break; sleep 1; done
    echo "== emulator shut down"
  fi
}
trap cleanup EXIT

# the known speech: for the microphone (32 kHz samples), and a two-minute blessing for step 5
SPEECH=integration_test/audio
limit 60 ffmpeg -v error -y -i $SPEECH/en.m4a -ac 1 -ar 32000 -f s16le $WORK/mic.pcm || exit 1
limit 120 ffmpeg -v error -y -i $SPEECH/en.m4a -i $SPEECH/es.m4a -filter_complex \
  "[0:a]aresample=32000,asplit=3[a][b][c];[1:a]aresample=32000,asplit=2[d][e];[a][d][b][e][c]concat=n=5:v=0:a=1" \
  -ac 1 -c:a aac -b:a 24k $WORK/two_minutes.m4a || exit 1

BYTES=$(stat -f %z "$MODEL")
if [[ "$*" == *sum* ]]; then # the wrong-checksum step needs its own build: the same app told to expect another SHA-256
  limit 900 flutter build apk --debug --target-platform android-arm64 \
    --dart-define=WORDS_MODEL_URL=http://10.0.2.2:$PORT/$(basename "$MODEL") --dart-define=WORDS_MODEL_BYTES="$BYTES" \
    --dart-define=WORDS_MODEL_SHA256=$(printf '0%.0s' $(seq 64)) >/dev/null || { echo "the build failed"; exit 1; }
  cp build/app/outputs/flutter-apk/app-debug.apk $WORK/app-badsum.apk
fi
limit 900 flutter build apk --debug --target-platform android-arm64 \
  --dart-define=WORDS_MODEL_URL=http://10.0.2.2:$PORT/$(basename "$MODEL") --dart-define=WORDS_MODEL_BYTES="$BYTES" >/dev/null \
  || { echo "the build failed"; exit 1; }

python3 -I tool/model_server.py "$MODEL" --port $PORT --log "$OUT/requests.log" >"$OUT/server.log" 2>&1 &
server=$!

DEV=$(adb devices | awk '/^emulator-/{print $1; exit}')
if [[ -n "$DEV" ]]; then
  echo "an emulator is already running ($DEV); shut it down first, so this run starts it with -no-audio"
  exit 1
fi
echo "== booting $AVD"
emulator -avd "$AVD" -no-snapshot-load -no-boot-anim -no-audio -crash-report-mode never >"$OUT/emulator.log" 2>&1 &
started=1
for _ in $(seq 120); do
  DEV=$(adb devices | awk '/^emulator-/{print $1; exit}')
  [[ -n "$DEV" && "$(adb -s "$DEV" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && break
  sleep 2
done
[[ -n "$DEV" ]] || { echo "the emulator did not boot"; exit 1; }
echo "== on $DEV, Android $(adb -s "$DEV" shell getprop ro.build.version.release | tr -d '\r')"
# small emulator disks: Android's low-storage line lowered for this run only (put back at the end)
adb -s "$DEV" shell settings put global sys_storage_threshold_max_bytes 31457280
# a run that was stopped in its no-network steps leaves the emulator offline; start from online
adb -s "$DEV" shell 'cmd connectivity airplane-mode disable; svc wifi enable; svc data enable' >/dev/null 2>&1
sleep 5

limit 2400 python3 -I tool/android_words.py "$DEV" "$OUT" --apk build/app/outputs/flutter-apk/app-debug.apk "$@"
code=$?
echo "== requests the app made to the model server:"
cat "$OUT/requests.log" 2>/dev/null
exit $code
