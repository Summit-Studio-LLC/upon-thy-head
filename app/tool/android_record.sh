#!/bin/bash
# Android recording, unattended (docs/android-plan.md tasks 4 to 7): boots the emulator, installs a
# fresh debug build, runs tool/android_record.py (steps 1, 2, 4 and 5 of the acceptance: 40 s and
# Amen compared with what was heard; five force-stops, a swipe from recents and `am kill`; calls
# answered, declined and locked; Discard), and shuts the emulator down.
#
#   tool/android_record.sh [avd] [--only 1,2,4,5]       default Pixel_10_Pro
#   --only 1,2,3,4,5,6,10 adds 5 minutes locked (twice: notifications allowed, then refused),
#   back / recents / turning / 2 minutes on the home screen, and battery saver with
#   "Don't keep activities": about 30 minutes in all
#
# The emulator runs with `-no-audio`: with the Mac's audio on, emulator 36.5.11 hangs as soon as
# anything opens its microphone, and crashes on its own microphone feed (gRPC injectAudio). What
# the app hears is known speech given as samples (tool/android_mic.py). Results, screenshots and
# the pulled recordings land in build/android_record/<avd>/; summary.json holds every number.
set -uo pipefail
cd "$(dirname "$0")/.."
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"
AVD=Pixel_10_Pro
[[ $# -gt 0 && "$1" != --* ]] && { AVD=$1; shift; }
OUT=build/android_record/$AVD
RUN_LIMIT=1500 # seconds for steps 1, 2, 4 and 5 (about 15 minutes); --only with 3, 6 or 10 allows more
[[ "$*" == *--only*3* || "$*" == *--only*6* ]] && RUN_LIMIT=3300
mkdir -p "$OUT"

limit() { # limit SECONDS command...: stopped if it runs longer
  local s=$1; shift
  perl -e 'alarm shift; exec @ARGV or die "cannot run $ARGV[0]"' "$s" "$@"
  local code=$?
  [[ $code == 142 ]] && echo "TIMED OUT after ${s}s: $*"
  return $code
}

started=0
cleanup() {
  if [[ $started == 1 ]]; then
    adb -s "$DEV" emu kill >/dev/null 2>&1
    for _ in $(seq 60); do adb devices | grep -q "^$DEV" || break; sleep 1; done
    echo "== emulator shut down"
  fi
}
trap cleanup EXIT

PY=$(limit 300 python3 tool/android_mic.py setup | tail -1) || { echo "could not set up Python"; exit 1; }
SPEECH=integration_test/audio
# the known speech, about two minutes, no stretch of it like another: English, Spanish, and both reversed
limit 60 ffmpeg -v error -y -i $SPEECH/en.m4a -i $SPEECH/es.m4a -filter_complex \
  "[0:a]aresample=16000,asplit[a][a2];[1:a]aresample=16000,asplit[b][b2];[a2]areverse[ra];[b2]areverse[rb];[a][b][ra][rb]concat=n=4:v=0:a=1" \
  -ac 1 build/android_mic/fed.wav || exit 1
limit 60 "$PY" tool/android_mic.py prepare build/android_mic/fed.wav build/android_mic/fed32.pcm >/dev/null || exit 1

limit 600 flutter build apk --debug --target-platform android-arm64 >/dev/null || { echo "the build failed"; exit 1; }

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
adb -s "$DEV" shell settings put global sysui_demo_allowed 1
adb -s "$DEV" shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null
adb -s "$DEV" shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 >/dev/null
adb -s "$DEV" uninstall dev.summitstudio.uponthyhead >/dev/null 2>&1
# Pixel_10_Pro has about 600 MB free, and Android refuses an install that would leave less than its
# low-storage line (about 500 MB): lowered to 200 MB for this run only, and put back at the end.
adb -s "$DEV" shell settings put global sys_storage_threshold_max_bytes 209715200
restore() { adb -s "$DEV" shell settings delete global sys_storage_threshold_max_bytes >/dev/null 2>&1; }
limit 180 adb -s "$DEV" install build/app/outputs/flutter-apk/app-debug.apk >/dev/null || { echo "the install failed"; restore; exit 1; }

limit "$RUN_LIMIT" "$PY" tool/android_record.py "$DEV" "$OUT" "$@"
code=$?
adb -s "$DEV" uninstall dev.summitstudio.uponthyhead >/dev/null 2>&1
restore
echo "== results in $OUT/summary.json"
exit $code
