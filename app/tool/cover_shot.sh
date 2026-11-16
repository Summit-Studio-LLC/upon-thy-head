#!/bin/bash
# Renders assets/sky/cover.jpg, the plain sky laid over the app in the app switcher
# (integration_test/cover_shot_test.dart). Run again if the sky's look changes.
#
# The simulator's own screenshot is used (Flutter's capture leaves out the shader-drawn sky), with
# the status bar's strip cut off; Privacy.swift fills the window with it, aspect-fill.
#
#   tool/cover_shot.sh [simulator udid]
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
TMP="$(mktemp -d)"
timeout 600 flutter build ios --simulator --debug --target=integration_test/cover_shot_test.dart >/dev/null || { echo "build failed"; exit 1; }
timeout 600 flutter drive -d "$UDID" --driver=test_driver/integration_test.dart \
  --target=integration_test/cover_shot_test.dart 2>&1 | while IFS= read -r line; do
  case "$line" in
    *"SIMSHOT cover"*) sleep 1; xcrun simctl io "$UDID" screenshot "$TMP/full.png" >/dev/null 2>&1; echo "== shot" ;;
    *"All tests passed"*|*"Some tests failed"*) echo "$line" ;;
  esac
done
[[ -f "$TMP/full.png" ]] || { echo "no screenshot"; exit 1; }
# cut the status bar and the Dynamic Island (200 px at 3x)
ffmpeg -y -loglevel error -i "$TMP/full.png" -vf "crop=iw:ih-200:0:200" -q:v 3 assets/sky/cover.jpg
sips -g pixelWidth -g pixelHeight assets/sky/cover.jpg | tail -2
ls -l assets/sky/cover.jpg
