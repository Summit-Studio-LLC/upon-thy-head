#!/bin/bash
# Android's acceptance on the emulator (integration_test/android_test.dart): boots the emulator,
# runs the test's two parts with a real kill of the app between them, and shuts the emulator down.
#
#   tool/android_tests.sh [avd]            default Pixel_10_Pro
#   tool/android_tests.sh --ios [udid]     the same test on the iPhone simulator, for the
#                                          side-by-side screenshots (default: iPhone 17 Pro (clean))
#
# Part 1 runs on a fresh install seeded with the five samples; `--keep-app-running` keeps the app
# and its data when it ends. The app is then killed (`am force-stop`), and part 2 is a new process
# reading the store from disk. Every step has a time limit. Screenshots, the device's own, land
# in ../design/sim/android/test/ (test-<avd>/ for another emulator, test-ios/ for the iPhone).
set -uo pipefail
cd "$(dirname "$0")/.."
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"
PART_LIMIT=420 # seconds for each part, the build included

ios=0
if [[ "${1:-}" == "--ios" ]]; then ios=1; DEV="${2:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"; else AVD="${1:-Pixel_10_Pro}"; fi
if [[ $ios == 1 ]]; then OUT=../design/sim/android/test-ios
elif [[ "$AVD" == Pixel_10_Pro ]]; then OUT=../design/sim/android/test
else OUT=../design/sim/android/test-$AVD; fi
mkdir -p "$OUT"

limit() { # limit SECONDS command...: the command is stopped if it runs longer (perl's alarm, on every Mac)
  local s=$1; shift
  perl -e 'alarm shift; exec @ARGV or die' "$s" "$@"
  local code=$?
  [[ $code == 142 ]] && echo "TIMED OUT after ${s}s: $*"
  return $code
}

shot() {
  if [[ $ios == 1 ]]; then xcrun simctl io "$DEV" screenshot "$OUT/$1.png" >/dev/null 2>&1
  else adb -s "$DEV" exec-out screencap -p >"$OUT/$1.png"; fi
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

if [[ $ios == 0 ]]; then
  DEV=$(adb devices | awk '/^emulator-/{print $1; exit}')
  if [[ -z "$DEV" ]]; then
    echo "== booting $AVD"
    emulator -avd "$AVD" -no-snapshot-load -no-boot-anim -no-audio >/tmp/android_tests_emulator.log 2>&1 &
    started=1
    for _ in $(seq 120); do
      DEV=$(adb devices | awk '/^emulator-/{print $1; exit}')
      [[ -n "$DEV" && "$(adb -s "$DEV" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && break
      sleep 2
    done
    [[ -n "$DEV" ]] || { echo "the emulator did not boot"; exit 1; }
  fi
  echo "== on $DEV, Android $(adb -s "$DEV" shell getprop ro.build.version.release | tr -d '\r')"
  # the same clock in every screenshot
  adb -s "$DEV" shell settings put global sysui_demo_allowed 1
  adb -s "$DEV" shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null
  adb -s "$DEV" shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 >/dev/null
  # a fresh install: nothing left from an earlier run
  adb -s "$DEV" uninstall dev.summitstudio.uponthyhead >/dev/null 2>&1
else
  xcrun simctl status_bar "$DEV" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
fi

# One build for both parts. Android: installed once by part 1; only the emulators' arm64 is built.
# iPhone: installed fresh here, then the microphone, speech and location granted, so no permission
# question covers the screenshots (`flutter drive` installs over it and keeps the grants).
if [[ $ios == 0 ]]; then
  limit "$PART_LIMIT" flutter build apk --debug --target-platform android-arm64 --target=integration_test/android_test.dart >/dev/null || { echo "the build failed"; exit 1; }
  drive_app=(--use-application-binary=build/app/outputs/flutter-apk/app-debug.apk)
else
  limit "$PART_LIMIT" flutter build ios --simulator --debug --target=integration_test/android_test.dart >/dev/null || { echo "the build failed"; exit 1; }
  xcrun simctl uninstall "$DEV" dev.summitstudio.uponThyHead 2>/dev/null
  xcrun simctl install "$DEV" build/ios/iphonesimulator/Runner.app || { echo "the install failed"; exit 1; }
  tool/sim_permissions.sh grant "$DEV" >/dev/null 2>&1 || true
  drive_app=(--use-application-binary=build/ios/iphonesimulator/Runner.app)
fi

# Android, part 2: `flutter drive` would install the APK again, which needs room for a second
# copy and, when it fails, uninstalls the app with its data (the very thing part 2 checks). So the
# script starts the installed app itself, finds its Dart VM service in the log, and connects to
# that (--use-existing-app). The screenshots then come from the log too.
existing_app() {
  adb -s "$DEV" logcat -c
  # paused at start, as `flutter drive` starts it: the test waits for the driver, and the window
  # has its size by then
  adb -s "$DEV" shell am start -n dev.summitstudio.uponthyhead/.MainActivity --ez start-paused true >/dev/null
  local url=""
  for _ in $(seq 60); do
    url=$(adb -s "$DEV" logcat -d -s flutter:I | grep -o 'http://127.0.0.1:[0-9]*/[^ ]*/' | tail -1)
    [[ -n "$url" ]] && break
    sleep 1
  done
  [[ -n "$url" ]] || { echo "the app's VM service never appeared"; return 1; }
  local port=${url#http://127.0.0.1:}; port=${port%%/*}
  local host
  host=$(adb -s "$DEV" forward tcp:0 tcp:"$port")
  echo "http://127.0.0.1:${host}/${url#http://127.0.0.1:*/}"
}

failed=0
for part in 1 2; do
  echo "== part $part"
  log=$(mktemp)
  how=(--keep-app-running ${drive_app[@]+"${drive_app[@]}"})
  watcher=""
  if [[ $ios == 0 && $part == 2 ]]; then
    url=$(existing_app) || { failed=1; echo "$url"; break; }
    how=(--use-existing-app="$url")
    # the app's own log, for its DEVSHOT lines
    (limit "$PART_LIMIT" adb -s "$DEV" logcat -s flutter:I | while IFS= read -r line; do
      [[ "$line" == *DEVSHOT* ]] && shot "$(echo "${line##*DEVSHOT }" | tr -d '\r')"
      [[ "$line" == *"ANDROID TEST PART"* ]] && echo "$line"
    done) &
    watcher=$!
    disown "$watcher"
  fi
  limit "$PART_LIMIT" flutter drive -d "$DEV" --driver=test_driver/integration_test.dart \
    --target=integration_test/android_test.dart "${how[@]}" 2>&1 |
    while IFS= read -r line; do
      echo "$line" >>"$log"
      [[ -z "$watcher" && "$line" == *DEVSHOT* ]] && shot "${line##*DEVSHOT }"
      [[ "$line" =~ (All\ tests\ passed|Some\ tests\ failed|EXCEPTION|Expected:|Actual:|Which:|TIMED\ OUT|PART) ]] && echo "$line"
    done
  [[ -n "$watcher" ]] && { sleep 2; pkill -P "$watcher" 2>/dev/null; kill "$watcher" 2>/dev/null; adb -s "$DEV" forward --remove-all; }
  grep -q "All tests passed" "$log" || { failed=1; grep -A30 -m1 "EXCEPTION CAUGHT" "$log"; tail -40 "$log"; }
  rm -f "$log"
  # a real kill: the next part is a new process reading the store from disk
  if [[ $ios == 1 ]]; then xcrun simctl terminate "$DEV" dev.summitstudio.uponThyHead 2>/dev/null
  else adb -s "$DEV" shell am force-stop dev.summitstudio.uponthyhead; fi
  echo "== killed the app"
  [[ $failed == 1 ]] && break
done
[[ $ios == 0 ]] && adb -s "$DEV" shell am broadcast -a com.android.systemui.demo -e command exit >/dev/null
echo "$([[ $failed == 0 ]] && echo PASSED || echo FAILED)"
exit $failed
