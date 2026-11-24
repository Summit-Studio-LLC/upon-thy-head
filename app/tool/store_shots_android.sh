#!/bin/bash
# The Google Play screenshots (integration_test/store_shots_test.dart, the iPhone's test run on the
# Android emulator): seven screens, the emulator's own screenshots, plain, into <out dir> as
# 01-home.png … 07-sharing.png.
#
#   tool/store_shots_android.sh <en|es> <out dir> [avd]        default avd Pixel_10_Pro
#
# The emulator is booted with -no-audio (with the Mac's audio on, it hangs when the microphone
# opens; docs/android-plan.md section 13) and shut down at the end unless it was already running.
# Spanish is the app's own language only (`cmd locale set-app-locales`), put back at the end; the
# Mac's language and the emulator's are never touched. The status bar is Android's demo mode: 9:41,
# full battery, signal and Wi-Fi, no notification icons; turned off again at the end. Nothing
# contacts any server: the share sheet is stopped at its choices.
#
# The app is installed once with adb (the Pixel_10_Pro's storage has no room for `flutter drive`'s
# second copy), its permissions granted, then started paused and the test attached to it, as
# tool/android_tests.sh part 2 does. The review page's recording (integration_test/audio) is put in
# the app's own files folder for the test to copy; nothing plays it.
#
# Android 17's status bar ignores demo mode's mobile and notification commands, so for the run the
# emulator's modem is set to full signal (`adb emu gsm signal-profile 4`, the emulator's own state,
# gone at its next boot), mobile data is turned off (no "3G"/"LTE" beside the bars; put back at the
# end) and any notification is snoozed for 30 minutes (Android brings it back itself).
set -uo pipefail
LANG_CODE="${1:?en or es}"
OUT_DIR="$(mkdir -p "${2:?out dir}" && cd "$2" && pwd)"
AVD="${3:-Pixel_10_Pro}"
[[ "$LANG_CODE" == en || "$LANG_CODE" == es ]] || { echo "en or es"; exit 2; }
cd "$(dirname "$0")/.."
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"
PKG=dev.summitstudio.uponthyhead
LOCK=/tmp/upon-thy-head-build.lock
# the app's own files folder (filled through run-as, as a debug build allows)
DEVICE_AUDIO=/data/user/0/$PKG/files/store_audio
APK=build/app/outputs/flutter-apk/app-debug.apk

limit() { # limit SECONDS command...: stopped if it runs longer
  local s=$1; shift
  perl -e 'alarm shift; exec @ARGV or die "cannot run $ARGV[0]"' "$s" "$@"
  local code=$?
  [[ $code == 142 ]] && echo "TIMED OUT after ${s}s: $*"
  return $code
}

started=0
DEV=""
mobile_data=""
watcher=""
cleanup() {
  [[ -n "$watcher" ]] && { pkill -P "$watcher" 2>/dev/null; kill "$watcher" 2>/dev/null; }
  if [[ -n "$DEV" ]]; then
    adb -s "$DEV" forward --remove-all >/dev/null 2>&1
    adb -s "$DEV" shell am force-stop $PKG >/dev/null 2>&1
    adb -s "$DEV" shell cmd locale set-app-locales $PKG --locales '""' >/dev/null 2>&1
    adb -s "$DEV" shell am broadcast -a com.android.systemui.demo -e command exit >/dev/null 2>&1
    adb -s "$DEV" shell settings put global sysui_demo_allowed 0 >/dev/null 2>&1
    adb -s "$DEV" uninstall $PKG >/dev/null 2>&1
    adb -s "$DEV" shell settings delete global sys_storage_threshold_max_bytes >/dev/null 2>&1
    [[ "$mobile_data" == 1 ]] && adb -s "$DEV" shell svc data enable >/dev/null 2>&1
  fi
  if [[ $started == 1 ]]; then
    adb -s "$DEV" emu kill >/dev/null 2>&1
    for _ in $(seq 60); do adb devices | grep -q "^$DEV" || break; sleep 1; done
    echo "== emulator shut down"
  fi
}
trap cleanup EXIT

# ---- the build (the defines are compiled in; the folder is the device's) ----
lockf -t 3600 "$LOCK" timeout 900 flutter build apk --debug --target-platform android-arm64 \
  --dart-define=SPEECH_AUDIO="$DEVICE_AUDIO" --target=integration_test/store_shots_test.dart >/dev/null ||
  { echo "build failed"; exit 1; }

# ---- the emulator ----
DEV=$(adb devices | awk '/^emulator-/{print $1; exit}')
if [[ -z "$DEV" ]]; then
  echo "== booting $AVD"
  emulator -avd "$AVD" -no-snapshot-load -no-boot-anim -no-audio -crash-report-mode never >/tmp/store_shots_android_emulator.log 2>&1 &
  started=1
  for _ in $(seq 120); do
    DEV=$(adb devices | awk '/^emulator-/{print $1; exit}')
    [[ -n "$DEV" && "$(adb -s "$DEV" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && break
    sleep 2
  done
  [[ -n "$DEV" ]] || { echo "the emulator did not boot"; exit 1; }
  sleep 5
else
  echo "== using the running $DEV (it must have been started with -no-audio)"
fi
echo "== on $DEV, Android $(adb -s "$DEV" shell getprop ro.build.version.release | tr -d '\r')"

# ---- the status bar: demo mode ----
demo() { adb -s "$DEV" shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null; }
adb -s "$DEV" shell settings put global sysui_demo_allowed 1
demo enter
demo clock -e hhmm 0941
demo battery -e level 100 -e plugged false -e powersave false
demo network -e wifi show -e level 4 -e fully true
demo network -e mobile show -e datatype none -e level 4 -e fully true
demo network -e airplane hide -e nosim hide
demo notifications -e visible false
# what demo mode no longer covers on Android 17
mobile_data=$(adb -s "$DEV" shell settings get global mobile_data | tr -d '\r')
adb -s "$DEV" shell svc data disable
adb -s "$DEV" emu gsm signal-profile 4 >/dev/null
for k in $(adb -s "$DEV" shell cmd notification list | tr -d '\r'); do
  adb -s "$DEV" shell "cmd notification snooze --for 1800000 '$k'" >/dev/null
done
demo status -e volume hide -e bluetooth hide -e location hide -e alarm hide -e zen hide -e mute hide -e speakerphone hide -e cast hide -e hotspot hide -e tty hide -e eri hide -e sync hide

# ---- a fresh install, its permissions, its language ----
adb -s "$DEV" uninstall $PKG >/dev/null 2>&1
# the Pixel_10_Pro is nearly full: Android's low-storage line lowered for this run (put back at the end)
adb -s "$DEV" shell settings put global sys_storage_threshold_max_bytes 209715200
limit 180 adb -s "$DEV" install "$APK" >/dev/null || { echo "the install failed"; exit 1; }
for p in RECORD_AUDIO POST_NOTIFICATIONS ACCESS_COARSE_LOCATION; do
  adb -s "$DEV" shell pm grant $PKG android.permission.$p 2>/dev/null
done
adb -s "$DEV" shell run-as $PKG mkdir -p "$DEVICE_AUDIO"
for a in en es; do
  adb -s "$DEV" exec-in run-as $PKG sh -c "cat > $DEVICE_AUDIO/$a.m4a" <integration_test/audio/$a.m4a
done
if [[ "$LANG_CODE" == es ]]; then
  adb -s "$DEV" shell cmd locale set-app-locales $PKG --locales es-US
else
  adb -s "$DEV" shell cmd locale set-app-locales $PKG --locales '""'
fi
rm -f "$OUT_DIR"/[0-9][0-9]-*.png

# ---- the run: the app started paused, the test attached, each SIMSHOT line read from its log ----
adb -s "$DEV" logcat -c
adb -s "$DEV" shell am start -n $PKG/.MainActivity --ez start-paused true >/dev/null
url=""
for _ in $(seq 60); do
  url=$(adb -s "$DEV" logcat -d -s flutter:I | grep -o 'http://127.0.0.1:[0-9]*/[^ ]*/' | tail -1)
  [[ -n "$url" ]] && break
  sleep 1
done
[[ -n "$url" ]] || { echo "the app's VM service never appeared"; exit 1; }
port=${url#http://127.0.0.1:}; port=${port%%/*}
host=$(adb -s "$DEV" forward tcp:0 tcp:"$port")
url="http://127.0.0.1:${host}/${url#http://127.0.0.1:*/}"

(limit 900 adb -s "$DEV" logcat -s flutter:I | while IFS= read -r line; do
  line=$(echo "$line" | tr -d '\r')
  case "$line" in
    *SIMSHOT*) name="${line##*SIMSHOT }"; adb -s "$DEV" exec-out screencap -p >"$OUT_DIR/$name.png"; echo "== $name" ;;
    *"STORE SHOTS"*) echo "${line##*: }" ;;
  esac
done) 2>/dev/null &
watcher=$!
disown "$watcher"

log=$(mktemp)
lockf -t 3600 "$LOCK" timeout 900 flutter drive -d "$DEV" --driver=test_driver/integration_test.dart \
  --target=integration_test/store_shots_test.dart --use-existing-app="$url" >"$log" 2>&1
sleep 3
pkill -P "$watcher" 2>/dev/null; kill "$watcher" 2>/dev/null; watcher=""
grep -q "All tests passed" "$log" || { echo "the test failed:"; grep -A30 -m1 "EXCEPTION CAUGHT" "$log"; tail -30 "$log"; }
rm -f "$log"

# plain RGB, no alpha channel
for f in "$OUT_DIR"/[0-9][0-9]-*.png; do
  [[ -s "$f" ]] && magick "$f" -background black -alpha remove -alpha off -define png:color-type=2 "$f"
done
for f in "$OUT_DIR"/[0-9][0-9]-*.png; do
  [[ -f "$f" ]] && echo "$(basename "$f") $(sips -g pixelWidth -g pixelHeight -g hasAlpha "$f" | awk '/pixel|hasAlpha/ {printf "%s ", $2}')"
done
[[ "$(ls "$OUT_DIR"/[0-9][0-9]-*.png 2>/dev/null | wc -l | tr -d ' ')" -eq 7 ]] && exit 0
exit 1
