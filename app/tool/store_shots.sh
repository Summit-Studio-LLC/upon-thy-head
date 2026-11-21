#!/bin/bash
# The App Store screenshots (integration_test/store_shots_test.dart): seven screens, the simulator's
# own screenshots, plain, into <out dir> as 01-home.png … 07-sharing.png.
#
#   tool/store_shots.sh <simulator udid> <en|es> <out dir>
#
# Spanish is set as tool/spanish_acceptance.sh sets it: the app's own language, in the app's
# preferences inside the simulator (as iOS Settings > Upon Thy Head > Language does). The Mac's own
# language and the simulator's are never touched; the app's preference is removed again at the end.
# The status bar reads 9:41, full battery and signal. Nothing contacts any server: the share sheet
# is stopped at its choices.
set -uo pipefail
UDID="${1:?simulator udid}"
LANG_CODE="${2:?en or es}"
# the out dir as given, from where the script was run
OUT_DIR="$(mkdir -p "${3:?out dir}" && cd "$3" && pwd)"
cd "$(dirname "$0")/.."
BUNDLE=dev.summitstudio.uponThyHead
AUDIO="$PWD/integration_test/audio"
LOCK=/tmp/upon-thy-head-build.lock
[[ "$LANG_CODE" == en || "$LANG_CODE" == es ]] || { echo "en or es"; exit 2; }

xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true

# the app installed, then its language set in its own preferences (an install keeps them)
DEFINES=(--dart-define=SPEECH_AUDIO="$AUDIO")
lockf -t 3600 "$LOCK" timeout 900 flutter build ios --simulator --debug "${DEFINES[@]}" \
  --target=integration_test/store_shots_test.dart >/dev/null || { echo "build failed"; exit 1; }
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
cleanup() {
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLanguages 2>/dev/null || true
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLocale 2>/dev/null || true
}
trap cleanup EXIT
if [[ "$LANG_CODE" == es ]]; then
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLanguages -array es
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLocale es_US
else
  cleanup
fi
tool/sim_permissions.sh grant "$UDID" >/dev/null
rm -f "$OUT_DIR"/[0-9][0-9]-*.png

status=1
lockf -t 3600 "$LOCK" timeout 900 flutter drive -d "$UDID" --driver=test_driver/integration_test.dart \
  --target=integration_test/store_shots_test.dart "${DEFINES[@]}" 2>&1 |
  while IFS= read -r line; do
    echo "$line"
    case "$line" in
      *SIMSHOT*) name="${line##*SIMSHOT }"; xcrun simctl io "$UDID" screenshot "$OUT_DIR/$name.png" >/dev/null 2>&1 ;;
    esac
  done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
# App Store Connect refuses screenshots with an alpha channel: flatten them to plain RGB
for f in "$OUT_DIR"/[0-9][0-9]-*.png; do
  [[ -f "$f" ]] && magick "$f" -background black -alpha remove -alpha off -define png:color-type=2 "$f"
done
for f in "$OUT_DIR"/[0-9][0-9]-*.png; do
  [[ -f "$f" ]] && echo "$(basename "$f") $(sips -g pixelWidth -g pixelHeight -g hasAlpha "$f" | awk '/pixel|hasAlpha/ {printf "%s ", $2}')"
done
[[ "$(ls "$OUT_DIR"/[0-9][0-9]-*.png 2>/dev/null | wc -l)" -eq 7 ]] && status=0
exit $status
