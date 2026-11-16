#!/bin/bash
# Microphone and speech-recognition permission for the app on a simulator, without the prompts.
#
#   tool/sim_permissions.sh grant|deny|reset [simulator udid]
#
# Location goes with them (granted, revoked or reset), so a test that opens the recording screen
# never meets the location question; the location acceptance resets it on purpose.
#
# `xcrun simctl privacy` covers the microphone but has no speech-recognition service, so that one
# is written into the simulator's own permission database (Library/TCC/TCC.db) and its permission
# daemon is restarted. Simulators only; a phone is never touched.
set -euo pipefail
ACTION="${1:?grant, deny or reset}"
UDID="${2:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
DB="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/TCC/TCC.db"
case "$ACTION" in
  grant) xcrun simctl privacy "$UDID" grant microphone "$BUNDLE"; xcrun simctl privacy "$UDID" grant location "$BUNDLE"; VALUE=2 ;;
  deny) xcrun simctl privacy "$UDID" revoke microphone "$BUNDLE"; xcrun simctl privacy "$UDID" revoke location "$BUNDLE"; VALUE=0 ;;
  reset) xcrun simctl privacy "$UDID" reset microphone "$BUNDLE" || true; xcrun simctl privacy "$UDID" reset location "$BUNDLE" || true; VALUE= ;;
  *) echo "grant, deny or reset" >&2; exit 2 ;;
esac
sqlite3 "$DB" "DELETE FROM access WHERE service = 'kTCCServiceSpeechRecognition' AND client = '$BUNDLE';"
if [[ -n "$VALUE" ]]; then
  sqlite3 "$DB" "INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags)
    VALUES ('kTCCServiceSpeechRecognition', '$BUNDLE', 0, $VALUE, 2, 1, 0);"
fi
xcrun simctl spawn "$UDID" launchctl kill TERM system/com.apple.tccd 2>/dev/null || true
echo "$ACTION: microphone, speech recognition and location for $BUNDLE"
