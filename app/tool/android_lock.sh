#!/bin/bash
# The Android app lock, the recent-apps cover and location, unattended (docs/android-plan.md tasks
# 11 and 12): builds a debug APK seeded for the first run, boots the emulator with its audio off,
# gives it a PIN and a fingerprint (tool/android_fingerprint.py), runs tool/android_lock.py
# (acceptance steps 1, 2, 3, 6 and 9, with 7 on the way), then uninstalls the app, takes the PIN
# and fingerprint away again, puts the storage settings back as they were, and shuts it down.
#
#   tool/android_lock.sh [avd] [--only 1,2,3,6,9]       default Pixel_10_Pro; the Pixel 3a is
#                                                      Pixel_3a_API_34_extension_level_7_arm64-v8a
#
# Results, screenshots and summary.json land in build/android_lock/<avd>/. Every step has a limit.
set -uo pipefail
cd "$(dirname "$0")/.."
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"
AVD=Pixel_10_Pro
[[ $# -gt 0 && "$1" != --* ]] && { AVD=$1; shift; }
OUT=build/android_lock/$AVD
PIN=1111
APK=build/app/outputs/flutter-apk/app-debug.apk
mkdir -p "$OUT"

limit() { # limit SECONDS command...: stopped if it runs longer
  local s=$1; shift
  perl -e 'alarm shift; exec @ARGV or die "cannot run $ARGV[0]"' "$s" "$@"
  local code=$?
  [[ $code == 142 ]] && echo "TIMED OUT after ${s}s: $*"
  return $code
}

started=0
DEV=""
saved_max="" saved_pct=""
cleanup() {
  local rc=$?
  if [[ -n "$DEV" ]]; then
    adb -s "$DEV" uninstall dev.summitstudio.uponthyhead >/dev/null 2>&1
    adb -s "$DEV" shell cmd location set-location-enabled true >/dev/null 2>&1
    limit 60 python3 tool/android_fingerprint.py "$DEV" remove $PIN
    # the storage settings as they were found
    for kv in "sys_storage_threshold_max_bytes:$saved_max" "sys_storage_threshold_percentage:$saved_pct"; do
      k=${kv%%:*}; v=${kv#*:}
      if [[ "$v" == null || -z "$v" ]]; then adb -s "$DEV" shell settings delete global "$k" >/dev/null 2>&1
      else adb -s "$DEV" shell settings put global "$k" "$v"; fi
    done
  fi
  if [[ $started == 1 ]]; then
    adb -s "$DEV" emu kill >/dev/null 2>&1
    for _ in $(seq 60); do adb devices | grep -q "^$DEV" || break; sleep 1; done
    echo "== emulator shut down"
  fi
  exit $rc
}
trap cleanup EXIT

limit 600 flutter build apk --debug --target-platform android-arm64 --dart-define=SEED_SAMPLES=first-run >/dev/null || { echo "the build failed"; exit 1; }

if [[ -n "$(adb devices | awk '/^emulator-/{print $1; exit}')" ]]; then
  echo "an emulator is already running; shut it down first, so this run starts it with -no-audio"
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
# Pixel_10_Pro has about 450 MB free and the debug APK is 170 MB: Android's low-storage lines (a
# size and a percentage) are lowered for this run and put back as they were at the end
saved_max=$(adb -s "$DEV" shell settings get global sys_storage_threshold_max_bytes | tr -d '\r')
saved_pct=$(adb -s "$DEV" shell settings get global sys_storage_threshold_percentage | tr -d '\r')
adb -s "$DEV" shell settings put global sys_storage_threshold_max_bytes 209715200
adb -s "$DEV" shell settings put global sys_storage_threshold_percentage 1
adb -s "$DEV" uninstall dev.summitstudio.uponthyhead >/dev/null 2>&1
limit 180 python3 tool/android_fingerprint.py "$DEV" add $PIN || { echo "could not enrol a fingerprint"; exit 1; }
limit 240 adb -s "$DEV" install "$APK" >/dev/null || { echo "the install failed"; exit 1; }

limit 1500 python3 tool/android_lock.py "$DEV" "$OUT" "$APK" $PIN "$@"
code=$?
echo "== results in $OUT/summary.json"
exit $code
