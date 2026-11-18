#!/bin/bash
# Entering a past blessing on the simulator (integration_test/entry_acceptance_test.dart).
#
#   lockf -t 3600 /tmp/upon-thy-head-build.lock tool/entry_acceptance.sh [simulator udid]
#   START=3 tool/entry_acceptance.sh [udid]   carry on from phase 3 with the data already there
#
# 1. The simulator is shut down and booted fresh (waiting for bootstatus); others are left alone.
# 2. The app is removed, then run as it was at commit 51932fd (taken from git into a temporary
#    folder; nothing in this checkout changes) with a small test of its own that writes its store:
#    the five sample blessings (kept running when done: flutter drive otherwise uninstalls the app).
# 3. The website (../website, `pnpm start` on 4319, links kept in a new temporary folder) starts
#    here; this build is made with the test as its target and LINK_SERVICE=http://127.0.0.1:4319
#    (never the live service), and installed over the old app, keeping its data. The alert tapper
#    (tool/alerts) answers the system's Allow Paste and swipes share sheets away.
# 4. Each phase is a new launch (simctl launch); the app is terminated between them. Phase 1 ends
#    with the app killed on the entry page, words typed and no date. Before phase 4 the app's own
#    language is set to Spanish (the simulator's and the Mac's are left alone); before phase 5 the
#    largest text size. Both are put back at the end, and the simulator shut down.
#
# Screenshots: ../design/sim/entry/ (Spanish in es/, the largest text in ax/).
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
OLD=51932fd
OUT_DIR="$(cd .. && pwd)/design/sim/entry"
WEBSITE="$(cd ../website && pwd)"
LIMIT="${LIMIT:-900}" # seconds per phase
TMP="$(mktemp -d)"
LINKS="$TMP/links"
TAP_DIR="$TMP/tapper"
DD="${TMPDIR:-/tmp}/uth_tapper_dd"
START="${START:-1}"
mkdir -p "$OUT_DIR/es" "$OUT_DIR/ax" "$LINKS"
[[ "$START" == 1 ]] && rm -f "$OUT_DIR"/*.png "$OUT_DIR"/es/*.png "$OUT_DIR"/ax/*.png

# the Mac's own language must not change: say what it is, and check it again at the end
MAC_LANG="$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n')"
echo "== the Mac's languages: $MAC_LANG"

WEB_PID="" TAPPER_PID="" LOG_PID=""
restore() {
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLanguages 2>/dev/null || true
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLocale 2>/dev/null || true
  xcrun simctl ui "$UDID" content_size large 2>/dev/null || true
}
tapper() {
  [[ -d "$TAP_DIR" ]] || { echo "no tapper"; return; }
  rm -f "$TAP_DIR/out"
  echo "$*" >"$TAP_DIR/cmd.tmp" && mv "$TAP_DIR/cmd.tmp" "$TAP_DIR/cmd"
  for _ in $(seq 1 "${TAP_WAIT:-160}"); do [[ -f "$TAP_DIR/out" ]] && break; sleep 0.25; done
  cat "$TAP_DIR/out" 2>/dev/null || echo "no answer"
}
cleanup() {
  [[ -n "$TAPPER_PID" ]] && { tapper quit >/dev/null; sleep 1; kill "$TAPPER_PID" 2>/dev/null; }
  [[ -n "$LOG_PID" ]] && kill "$LOG_PID" 2>/dev/null
  [[ -n "$WEB_PID" ]] && kill "$WEB_PID" 2>/dev/null
  lsof -ti tcp:4319 -sTCP:LISTEN | xargs kill 2>/dev/null
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  restore
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  local now; now="$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n')"
  [[ "$now" == "$MAC_LANG" ]] && echo "== the Mac's languages unchanged: $now" || echo "== THE MAC'S LANGUAGES CHANGED: $MAC_LANG -> $now"
  rm -rf "$TMP"
}
trap cleanup EXIT

# ---- 1. a fresh boot ----
xcrun simctl shutdown "$UDID" 2>/dev/null || true
timeout 300 xcrun simctl bootstatus "$UDID" -b >/dev/null || { echo "the simulator did not boot"; exit 1; }
echo "== booted $UDID"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
restore

# ---- 2. the store as the app at 51932fd wrote it ----
if [[ "$START" == 1 ]]; then
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
git -C .. archive "$OLD" app | tar -x -C "$TMP" || { echo "could not take $OLD from git"; exit 1; }
cat >"$TMP/app/integration_test/entry_seed_test.dart" <<'DART'
// Written by tool/entry_acceptance.sh into the app as it was at 51932fd: its own store, its own code.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('the store before entered blessings: the five samples', (t) async {
    final store = await freshSeededStore();
    expect(await store.list(), hasLength(5));
    debugPrint('SEEDED ${(await store.list()).length}');
    await store.close();
  });
}
DART
tool/sim_permissions.sh grant "$UDID" >/dev/null
( cd "$TMP/app" && timeout 900 flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/entry_seed_test.dart --keep-app-running ) >"$TMP/seed.txt" 2>&1
grep -q "SEEDED 5" "$TMP/seed.txt" && grep -q "All tests passed" "$TMP/seed.txt" || { echo "== the $OLD app did not write its store"; tail -30 "$TMP/seed.txt"; exit 1; }
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
echo "== the app at $OLD wrote five blessings"
fi

# ---- 3. the website, the tapper, this build over it ----
lsof -ti tcp:4319 -sTCP:LISTEN | xargs kill 2>/dev/null
(cd "$WEBSITE" && LINKS_LOCAL_DIR="$LINKS" exec timeout 5400 pnpm start -p 4319 >>"$TMP/web.txt" 2>&1) &
WEB_PID=$!
for _ in $(seq 1 60); do curl -s -o /dev/null --max-time 2 http://127.0.0.1:4319/api/b/x && break; sleep 0.5; done
curl -s -o /dev/null --max-time 2 http://127.0.0.1:4319/api/b/x || { echo "the website did not start"; tail -20 "$TMP/web.txt"; exit 1; }
echo "== the website is up on 4319"

timeout 600 xcodebuild build-for-testing -project tool/alerts/Tapper.xcodeproj -scheme TapperUITests \
  -destination "id=$UDID" -derivedDataPath "$DD" >"$TMP/tapper_build.txt" 2>&1 || { echo "tapper build failed"; tail -20 "$TMP/tapper_build.txt"; exit 1; }
XCTESTRUN="$(ls "$DD"/Build/Products/*.xctestrun | head -1)"
mkdir -p "$TAP_DIR"
TEST_RUNNER_TAPPER_DIR="$TAP_DIR" TEST_RUNNER_RUN_SECONDS=5400 timeout 5600 \
  xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "id=$UDID" >"$TMP/tapper.txt" 2>&1 &
TAPPER_PID=$!
for _ in $(seq 1 120); do [[ -f "$TAP_DIR/ready" ]] && break; sleep 1; done
[[ -f "$TAP_DIR/ready" ]] || { echo "tapper did not start"; tail -20 "$TMP/tapper.txt"; exit 1; }
echo "== the tapper is up"

timeout 900 flutter build ios --simulator --debug --target=integration_test/entry_acceptance_test.dart \
  --dart-define=LINK_SERVICE=http://127.0.0.1:4319 >"$TMP/build.txt" 2>&1 || { echo "build failed"; tail -20 "$TMP/build.txt"; exit 1; }
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
ACTS="$DATA/tmp/entryacts"
rm -rf "$ACTS" "$DATA/Documents/entry_test_status"
if [[ "$START" == 1 ]]; then rm -f "$DATA/Documents/entry_test_"*; fi
mkdir -p "$ACTS"
touch "$DATA/Documents/entry_test_log.txt"
tail -n 0 -F "$DATA/Documents/entry_test_log.txt" 2>/dev/null | sed -u 's/^/   test: /' &
LOG_PID=$!
tool/sim_permissions.sh grant "$UDID" >/dev/null

answer() {
  local n="$1"; shift
  local what="$*" ans="ok"
  case "$what" in
    "shot "*) xcrun simctl io "$UDID" screenshot "$OUT_DIR/${what#shot }.png" >/dev/null 2>&1 || ans="screenshot failed" ;;
    "pbcopy "*)
      echo "${what#pbcopy }" | base64 -d | xcrun simctl pbcopy "$UDID" || ans="pbcopy failed"
      # iOS asks before an app reads what another app copied, and the app waits on the answer (its
      # main thread is held), so the test cannot ask for it: it is watched for here, shown, and a
      # person's Allow Paste given
      rm -f "$TMP/allowpaste.txt"
      ( for _ in $(seq 1 30); do
          d="$(tapper alert)"
          if [[ "$d" == *aste* || "$d" == *egar* ]]; then
            xcrun simctl io "$UDID" screenshot "$OUT_DIR/04b-allow-paste.png" >/dev/null 2>&1
            echo "asked: ${d:0:100}; $(tapper tap 'Allow Paste' | cut -c1-40)" >"$TMP/allowpaste.txt"; exit 0
          fi
          sleep 1
        done; echo "never asked" >"$TMP/allowpaste.txt" ) & ;;
    "allowpaste")
      for _ in $(seq 1 60); do [[ -f "$TMP/allowpaste.txt" ]] && break; sleep 1; done
      ans="$(cat "$TMP/allowpaste.txt" 2>/dev/null || echo 'no answer')" ;;
    "appdismiss "*) ans="$(tapper appdismiss)" ;;
    "web "*)
      set -- ${what#web }
      ans="$(timeout 60 node tool/link_web.mjs "$1" "$OUT_DIR/$2.png" 2>&1 | tail -1)" ;;
    *) ans="unknown" ;;
  esac
  echo "== ACT $n ${what:0:60} -> ${ans:0:160}" >&2
  echo "$ans" >"$ACTS/act_$n.tmp" && mv "$ACTS/act_$n.tmp" "$ACTS/act_$n"
}

serve() {
  local end=$((SECONDS + LIMIT)) st=""
  while ((SECONDS < end)); do
    for ask in "$ACTS"/ask_*; do
      [[ -f "$ask" ]] || continue
      local n="${ask##*_}"
      [[ "$n" == *.tmp ]] && continue
      local what; what="$(cat "$ask")"; rm -f "$ask"
      answer "$n" "$what"
    done
    if [[ -f "$DATA/Documents/entry_test_status" ]]; then st="$(cat "$DATA/Documents/entry_test_status")"; break; fi
    sleep 0.2
  done
  echo "${st:-timed out}"
}

# ---- 4. the phases ----
status=1
phase=$START
[[ "$START" != 1 ]] && echo "{\"phase\": $START}" >"$DATA/Documents/entry_test_phase"
while :; do
  echo "== phase $phase"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 2
  rm -f "$DATA/Documents/entry_test_status"
  restore
  case "$phase" in
    4) xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLanguages -array es
       xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLocale es_US ;;
    5) xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large ;;
  esac
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  got="$(serve)"
  echo "== phase $phase: $got"
  case "$got" in
    "next "*)
      # phase 1 leaves the app on the entry page with words typed: it is killed there
      [[ "$phase" == 1 ]] && { sleep 1; xcrun simctl spawn "$UDID" launchctl list | grep -q "$BUNDLE" && echo "== killing the app on the entry page"; }
      phase="${got#next }" ;;
    done) status=0; echo "== ALL PHASES PASSED"; break ;;
    *) echo "== phase $phase FAILED"; break ;;
  esac
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
ls "$OUT_DIR" "$OUT_DIR/es" "$OUT_DIR/ax" | sed 's/^/   /'
exit $status
