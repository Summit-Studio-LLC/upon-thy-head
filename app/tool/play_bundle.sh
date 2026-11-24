#!/bin/bash
# The release App Bundle for Google Play, signed with the upload key.
#
#   tool/play_bundle.sh
#
# Needs android/key.properties (see important/readme.txt). The version code is pubspec's +N, the
# same counter as the iPhone build; Play refuses a code it has already seen on any track.
# Uploading is done in Play Console: there is no Play API key on this Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f android/key.properties ]] || { echo "android/key.properties is missing: see important/readme.txt"; exit 1; }
STAMP="$(mktemp)"; trap 'rm -f "$STAMP"' EXIT
flutter build appbundle --release --target-platform android-arm64,android-x64
AAB=build/app/outputs/bundle/release/app-release.aab
[[ -f "$AAB" && "$AAB" -nt "$STAMP" ]] || { echo "no fresh $AAB came out of this build"; exit 1; }
WANT="$(keytool -list -v -keystore "$(sed -n 's/^storeFile=//p' android/key.properties)" \
  -storepass "$(sed -n 's/^storePassword=//p' android/key.properties)" 2>/dev/null | sed -n 's/.*SHA256: //p' | head -1)"
GOT="$(keytool -printcert -jarfile "$AAB" | sed -n 's/.*SHA256: //p' | head -1)"
[[ -n "$WANT" && "$WANT" == "$GOT" ]] || { echo "the bundle is not signed with the upload key ($GOT)"; exit 1; }
echo "$AAB  $(sed -nE 's/^version: *//p' pubspec.yaml)  $(du -h "$AAB" | cut -f1)  signed with the upload key"
