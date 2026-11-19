#!/bin/bash
# One quick look at handing a ring over (integration_test/hand_over_shot_test.dart) on an iPhone
# simulator, against the website running here (`pnpm start` on 4319, links kept in a new temporary
# folder): screenshots into ../design/sim/handover/. Never the live service.
#
#   tool/hand_over_shot.sh <simulator udid>
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="$1"
OUT_DIR="$(cd .. && pwd)/design/sim/handover"
WEBSITE="$(cd ../website && pwd)"
TMP="$(mktemp -d)"
mkdir -p "$OUT_DIR" "$TMP/links"
web_up() { curl -s -o /dev/null --max-time 2 http://127.0.0.1:4319/api/b/x; }
(cd "$WEBSITE" && LINKS_LOCAL_DIR="$TMP/links" exec timeout 1800 pnpm start -p 4319 >>"$TMP/web.txt" 2>&1) &
WEB_PID=$!
for _ in $(seq 1 60); do web_up && break; sleep 0.5; done
web_up || { echo "the website did not start"; tail -20 "$TMP/web.txt"; exit 1; }
trap 'kill $WEB_PID 2>/dev/null; lsof -ti tcp:4319 -sTCP:LISTEN | xargs kill 2>/dev/null' EXIT
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
tool/sim_permissions.sh grant "$UDID" >/dev/null
timeout 900 flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/hand_over_shot_test.dart \
  --dart-define=LINK_SERVICE=http://127.0.0.1:4319 2>&1 |
  while IFS= read -r line; do
    echo "$line"
    case "$line" in
      *SIMSHOT*) name="${line##*SIMSHOT }"; xcrun simctl io "$UDID" screenshot "$OUT_DIR/$name.png" >/dev/null 2>&1 ;;
    esac
  done
echo "copies the website kept: $(ls "$TMP/links" | wc -l)"
