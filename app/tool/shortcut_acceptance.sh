#!/bin/bash
# Spotlight → the app's App Shortcuts, replayed as a person does it, on the simulator: Home, a swipe
# down, "blessing" typed, the result tapped (tool/alerts/Tapper.swift `spotlight`, `spotlighttap`).
# Each tap goes through iOS itself: the intent's perform() (ios/Runner/Shortcuts.swift), then
# BlessingInbox, then Dart (lib/home/home_screen.dart, "shortcuts").
#
#   tool/shortcut_acceptance.sh [simulator udid]
#
# The app (SEED_SAMPLES=true, so the five samples and no first run) is installed fresh, with Face ID
# enrolled, so the lock is on as it is by default. Cases:
#   1  cold start, locked → Record a blessing: still locked while the phone asks for the face; a face
#      that does not match leaves the app locked, and it goes to the recording start (Begin) as the
#      locked New blessing button does (Noah, 2026-11-18): nothing recording, nothing of any
#      blessing shown
#   2  cold start, locked → Open my blessings: a match → home, the sky with its blessings
#   3  warm, on a reading page → Record a blessing → the recording start
#   4  warm, on the recording start → Open my blessings → home
#   5  warm, in Settings → Record a blessing → the recording start
# Screenshots land in ../design/sim/shortcuts/. The simulator is shut down at the end.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
OUT="$(cd .. && pwd)/design/sim/shortcuts"
TMP="$(mktemp -d)"
TAP_DIR="$TMP/tapper"
DD="${TMPDIR:-/tmp}/uth_tapper_dd"
mkdir -p "$OUT" "$TAP_DIR"
rm -f "$OUT"/*.png

echo "simulator: shut down, booted"
xcrun simctl shutdown "$UDID" 2>/dev/null
xcrun simctl boot "$UDID" && xcrun simctl bootstatus "$UDID" -b >/dev/null || { echo "boot failed"; exit 1; }
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true

timeout 900 flutter build ios --simulator --debug --dart-define=SEED_SAMPLES=true >"$TMP/build.txt" 2>&1 || { echo "build failed"; tail -20 "$TMP/build.txt"; exit 1; }
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null
# the app's own language on this simulator, left by a Spanish run: the phone's (English) instead
xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLanguages 2>/dev/null
xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLocale 2>/dev/null
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
face() { xcrun simctl spawn "$UDID" notifyutil -p "com.apple.BiometricKit_Sim.pearl.$1"; }
xcrun simctl spawn "$UDID" notifyutil -s com.apple.BiometricKit.enrollmentChanged 1
xcrun simctl spawn "$UDID" notifyutil -p com.apple.BiometricKit.enrollmentChanged

timeout 600 xcodebuild build-for-testing -project tool/alerts/Tapper.xcodeproj -scheme TapperUITests \
  -destination "id=$UDID" -derivedDataPath "$DD" >"$TMP/tapper_build.txt" 2>&1 || { echo "tapper build failed"; tail -20 "$TMP/tapper_build.txt"; exit 1; }
XCTESTRUN="$(ls "$DD"/Build/Products/*.xctestrun | head -1)"
TEST_RUNNER_TAPPER_DIR="$TAP_DIR" TEST_RUNNER_RUN_SECONDS=1500 timeout 1600 \
  xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "id=$UDID" >"$TMP/tapper.txt" 2>&1 &
TAPPER_PID=$!
for _ in $(seq 1 120); do [[ -f "$TAP_DIR/ready" ]] && break; sleep 1; done
[[ -f "$TAP_DIR/ready" ]] || { echo "tapper did not start"; tail -20 "$TMP/tapper.txt"; exit 1; }
tapper() {
  rm -f "$TAP_DIR/out"
  echo "$*" >"$TAP_DIR/cmd.tmp" && mv "$TAP_DIR/cmd.tmp" "$TAP_DIR/cmd"
  for _ in $(seq 1 240); do [[ -f "$TAP_DIR/out" ]] && break; sleep 0.25; done
  cat "$TAP_DIR/out" 2>/dev/null || echo "no answer"
}
cleanup() {
  tapper quit >/dev/null; sleep 1; kill "$TAPPER_PID" 2>/dev/null
  xcrun simctl shutdown "$UDID" 2>/dev/null
}
trap cleanup EXIT

FAILS=0
# The rows Spotlight lists for "blessing" are the app's two Core Spotlight entries (Shortcuts.swift):
# "Record a blessing" and this one, which opens home. Since those entries were added they take the
# place of the App Shortcuts' own rows, so "Open my blessings" is no longer listed there.
HOME_ROW="My priesthood blessings"
shot() { xcrun simctl io "$UDID" screenshot "$OUT/$1.png" >/dev/null 2>&1; }
labels() { tapper appall; }
# where the app is: record (the Begin screen: shown only before Begin, so nothing is recording), home (the unlocked sky), locked, or other
where() {
  local l; l="$(labels)"
  if [[ "$l" == *"Nothing is recorded until you press"* ]]; then echo record
  elif [[ "$l" == *"Locked"* || "$l" == *"Unlock"* ]]; then echo locked
  elif [[ "$l" == *"Show as a list"* && "$l" == *"New blessing"* ]]; then echo home
  else echo "other: $l"; fi
}
expect() { # name, wanted
  local got; got="$(where)"
  shot "$1"
  if [[ "$got" == "$2" ]]; then echo "PASS $1: $2"; else echo "FAIL $1: wanted $2, got $got"; FAILS=$((FAILS + 1)); fi
}
# the system's questions on the recording start, the first time (microphone, speech, then where
# blessings are given)
answer() { for _ in 1 2; do tapper tap Allow >/dev/null; done; sleep 2; tapper tap "Allow Once" >/dev/null; }
via_spotlight() { # result label: searched for and tapped, up to three tries
  local r=""
  for _ in 1 2 3; do
    tapper spotlight blessing >/dev/null
    r="$(tapper spotlighttap "$1")"
    [[ "$r" == ok* ]] && break
    tapper home >/dev/null
  done
  shot "spotlight-$(echo "$1" | tr ' A-Z' '-a-z')"
  if [[ "$r" != ok* ]]; then echo "FAIL Spotlight: \"$1\" $r"; FAILS=$((FAILS + 1)); return 1; fi
  echo "Spotlight lists \"$1\", tapped"
}

# opened once from its icon, unlocked, as a person would after installing it
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null; sleep 8; face match; sleep 4
expect 00-first-open home

# iOS indexes App Shortcuts some minutes after an install: Spotlight is asked every 30 s, up to 15 min
START=$(date +%s); LISTED=""
while (( $(date +%s) - START < 900 )); do
  tapper spotlight blessing >/dev/null
  r="$(tapper spotlightlabels)"; [[ "$r" != *"Record a blessing"* ]] && { tapper spotlightscroll >/dev/null; r="$(tapper spotlightlabels)"; }
  [[ "$r" == *"Record a blessing"* && "$r" == *"$HOME_ROW"* ]] && { LISTED=yes; break; }
  # what Spotlight showed this time, so a run that never lists them can be read afterwards
  echo "$(( $(date +%s) - START )) s: $(echo "$r" | tr '\n' '|' | cut -c1-700)" >> "$OUT/spotlight-polls.txt"
  tapper home >/dev/null; sleep 30
done
if [[ -z "$LISTED" ]]; then echo "FAIL Spotlight never listed the actions in 15 min"; shot spotlight-never; exit 1; fi
echo "Spotlight lists both actions $(( $(date +%s) - START )) s after the first open"
tapper home >/dev/null

echo "-- 1 cold, locked: Record a blessing"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null; sleep 1
via_spotlight "Record a blessing"; sleep 8
expect 01a-cold-record-locked locked
face nomatch; sleep 3
tapper tap Cancel >/dev/null
sleep 3
answer
expect 01b-cold-record-face-refused record

echo "-- 2 cold, locked: Open my blessings"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null; sleep 1
via_spotlight "$HOME_ROW"; sleep 8
expect 02a-cold-home-locked locked
face match; sleep 4
expect 02b-cold-home-unlocked home

echo "-- 3 warm, on a reading page: Record a blessing"
tapper apptap "Read this blessing" >/dev/null; sleep 2
[[ "$(labels)" == *"Before the new job"* ]] && echo "on the reading page"
via_spotlight "Record a blessing"; sleep 5
# away under a minute: not locked again, as from the icon
expect 03-warm-read-to-record record

echo "-- 4 warm, on the recording start: Open my blessings"
via_spotlight "$HOME_ROW"; sleep 5
expect 04-warm-record-to-home home

echo "-- 5 warm, in Settings: Record a blessing"
tapper apptap Settings >/dev/null; sleep 2
via_spotlight "Record a blessing"; sleep 5
expect 05-warm-settings-to-record record

echo "screenshots: $OUT"
[[ $FAILS -eq 0 ]] && echo "ALL PASSED" || echo "$FAILS FAILED"
exit $FAILS
