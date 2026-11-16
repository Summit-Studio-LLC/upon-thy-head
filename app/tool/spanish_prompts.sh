#!/bin/bash
# The system's own questions (microphone, speech recognition, location, the lock) on a phone set to
# Spanish. iOS words them by the phone's language, not the app's own, so the per-app language the
# Spanish acceptance uses (tool/spanish_acceptance.sh) leaves them in the simulator's English.
#
#   tool/spanish_prompts.sh
#
# Makes a temporary iPhone 17 Pro simulator set to Spanish (United States),
# installs the app built with SKY_START=listening (it opens a recording and presses Begin once the
# sky loads, which asks the three questions in turn), screenshots each question and answers it with
# tool/alerts, then deletes the simulator. No other simulator is touched.
#
# Screenshots: ../design/sim/spanish/prompts/.
set -uo pipefail
cd "$(dirname "$0")/.."
BUNDLE=dev.summitstudio.uponThyHead
OUT_DIR="$(cd .. && pwd)/design/sim/spanish/prompts"
TMP="$(mktemp -d)"
DD="$TMP/dd"
TAP_DIR="$TMP/tapper"
mkdir -p "$OUT_DIR" "$TAP_DIR"
rm -f "$OUT_DIR"/*.png

UDID="$(xcrun simctl create "UTH Spanish prompts (temporary)" "iPhone 17 Pro")" || { echo "could not create a simulator"; exit 1; }
echo "== temporary simulator $UDID"
cleanup() {
  [[ -n "${TAPPER_PID:-}" ]] && { echo quit >"$TAP_DIR/cmd"; sleep 1; kill "$TAPPER_PID" 2>/dev/null; }
  xcrun simctl shutdown "$UDID" 2>/dev/null
  xcrun simctl delete "$UDID" && echo "== deleted $UDID"
}
trap cleanup EXIT
# the phone's own language: set inside the booted simulator (a first boot rewrites preferences
# written beforehand), then restarted so the system's own alerts pick it up
xcrun simctl boot "$UDID"
timeout 300 xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array es-US es
xcrun simctl spawn "$UDID" defaults write -g AppleLocale es_US
xcrun simctl shutdown "$UDID"
xcrun simctl boot "$UDID"
timeout 300 xcrun simctl bootstatus "$UDID" -b >/dev/null
echo "== the phone's languages: $(xcrun simctl spawn "$UDID" defaults read -g AppleLanguages | tr -d ' \n')"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl location "$UDID" set 19.4326,-99.1332

timeout 600 xcodebuild build-for-testing -project tool/alerts/Tapper.xcodeproj -scheme TapperUITests \
  -destination "id=$UDID" -derivedDataPath "$DD" >"$TMP/tapper_build.txt" 2>&1 || { echo "tapper build failed"; tail -20 "$TMP/tapper_build.txt"; exit 1; }
XCTESTRUN="$(ls "$DD"/Build/Products/*.xctestrun | head -1)"
TEST_RUNNER_TAPPER_DIR="$TAP_DIR" TEST_RUNNER_RUN_SECONDS=600 timeout 700 \
  xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "id=$UDID" >"$TMP/tapper.txt" 2>&1 &
TAPPER_PID=$!
for _ in $(seq 1 180); do [[ -f "$TAP_DIR/ready" ]] && break; sleep 1; done
[[ -f "$TAP_DIR/ready" ]] || { echo "tapper did not start"; tail -20 "$TMP/tapper.txt"; exit 1; }
tapper() {
  rm -f "$TAP_DIR/out"
  echo "$*" >"$TAP_DIR/cmd.tmp" && mv "$TAP_DIR/cmd.tmp" "$TAP_DIR/cmd"
  for _ in $(seq 1 120); do [[ -f "$TAP_DIR/out" ]] && break; sleep 0.25; done
  cat "$TAP_DIR/out" 2>/dev/null || echo "no answer"
}

timeout 600 flutter build ios --simulator --debug --dart-define=SKY_START=listening >/dev/null || { echo "build failed"; exit 1; }
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
status=0
n=0
# the lock's passcode question comes first (no face is enrolled); the three questions follow as the
# recording opens, whether or not the lock is answered
for want in microphone speech location; do
  ans=""
  for _ in $(seq 1 40); do
    ans="$(tapper alert)"
    [[ "$ans" != none && "$ans" != "no answer" ]] && ! grep -qi "código" <<<"$ans" && break
    sleep 1
  done
  n=$((n + 1))
  sleep 1
  xcrun simctl io "$UDID" screenshot "$OUT_DIR/$n-$want.png" >/dev/null 2>&1
  echo "== $want: $ans"
  case "$want" in
    microphone) grep -q "Upon Thy Head escucha solo mientras grabas una bendición" <<<"$ans" || status=1; tapper tap Permitir ;;
    speech) grep -q "La voz se convierte en texto en este teléfono" <<<"$ans" || status=1; tapper tap Permitir ;;
    location) grep -q "Se usa una vez para poner la luz" <<<"$ans" || status=1; tapper tap "Permitir una vez" ;;
  esac
done
sleep 3
xcrun simctl io "$UDID" screenshot "$OUT_DIR/4-recording.png" >/dev/null 2>&1
[[ $status == 0 ]] && echo "== ALL THREE IN SPANISH" || echo "== NOT ALL IN SPANISH"
exit $status
