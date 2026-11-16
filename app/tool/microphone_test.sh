#!/bin/bash
# The real-microphone check (integration_test/microphone_test.dart): plays the spoken sample
# through the Mac's speakers while the app listens on a simulator. Sets the output volume to
# $VOLUME (default 50) for the playback only, then puts it back as it was.
#
#   tool/microphone_test.sh [simulator udid]
set -euo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
SETTINGS="$(osascript -e 'get volume settings')"
OLD_VOL="$(sed -E 's/.*output volume:([0-9]+).*/\1/' <<<"$SETTINGS")"
OLD_MUTED="$(sed -E 's/.*output muted:(true|false).*/\1/' <<<"$SETTINGS")"
restore() { osascript -e "set volume output volume $OLD_VOL" -e "set volume output muted $OLD_MUTED"; }
trap restore EXIT
flutter build ios --simulator --debug >/dev/null
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
tool/sim_permissions.sh grant "$UDID"
flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/microphone_test.dart 2>&1 |
  while IFS= read -r line; do
    echo "$line"
    if [[ "$line" == *"flutter: PLAY"* ]]; then
      osascript -e "set volume output muted false" -e "set volume output volume ${VOLUME:-50}"
      afplay integration_test/audio/en.m4a
      restore
    fi
  done
