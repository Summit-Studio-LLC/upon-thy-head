#!/bin/bash
# Family members on the simulator (integration_test/family_test.dart), from an upgrade to the lock.
#
#   tool/family_acceptance.sh [simulator udid]
#   START=4 tool/family_acceptance.sh [udid]    carry on from phase 4 with the data already there
#                                               (no fresh boot, no store from 58341dc)
#
# 1. The simulator is shut down and booted fresh (waiting for bootstatus); others are left alone.
# 2. The app is removed, then run as it was at commit 58341dc (taken from git into a temporary
#    folder; nothing in this checkout changes) with a small test of its own that writes its store:
#    the five sample blessings and a draft (kept running when done: flutter drive otherwise
#    uninstalls the app, and its data with it). REPO=<checkout>: where to take it from (default: ..).
# 3. This build is installed over it, keeping that data, and family_test.dart runs once per phase
#    with --keep-app-running; the app is terminated between phases, so each is a new launch.
#    Before phase 4 the app's own language is set to Spanish (as iOS Settings > Upon Thy Head >
#    Language does; the simulator's language is left alone); before phase 5 the largest text size.
#    Both are put back at the end.
#    `ACT away <s>`: the Settings app is opened (this app goes to the background), and after <s>
#    seconds this app again. `ACT face match`: the Simulator's Face ID matches.
# 4. The simulator is shut down.
#
# Built with SPEECH_AUDIO (the recording hears the English passage). Every phase has a time limit.
# Screenshots: ../design/sim/family/ (Spanish in es/, the largest text in ax/).
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
BUNDLE=dev.summitstudio.uponThyHead
OLD=58341dc
AUDIO="$PWD/integration_test/audio"
OUT_DIR="$(cd .. && pwd)/design/sim/family"
LIMIT="${LIMIT:-720}" # seconds per phase
TMP="$(mktemp -d)"
mkdir -p "$OUT_DIR/es" "$OUT_DIR/ax"

face() { xcrun simctl spawn "$UDID" notifyutil -p "com.apple.BiometricKit_Sim.pearl.$1"; }
enrol() { xcrun simctl spawn "$UDID" notifyutil -s com.apple.BiometricKit.enrollmentChanged "$1"; xcrun simctl spawn "$UDID" notifyutil -p com.apple.BiometricKit.enrollmentChanged; }
cleanup() {
  xcrun simctl ui "$UDID" content_size large 2>/dev/null || true
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLanguages 2>/dev/null || true
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLocale 2>/dev/null || true
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

START="${START:-1}"
# ---- 1. a fresh boot ----
if [[ "$START" == 1 ]]; then
xcrun simctl shutdown "$UDID" 2>/dev/null || true
timeout 300 xcrun simctl bootstatus "$UDID" -b >/dev/null || { echo "the simulator did not boot"; exit 1; }
echo "== booted $UDID"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$UDID" content_size large || true
enrol 1

# ---- 2. the store as the app at 58341dc wrote it ----
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
git -C "${REPO:-..}" archive "$OLD" app | tar -x -C "$TMP" || { echo "could not take $OLD from git"; exit 1; }
cat >"$TMP/app/integration_test/family_seed_test.dart" <<'DART'
// Written by tool/family_acceptance.sh into the app as it was at 58341dc: its own store, its own code.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/data/blessing.dart';

import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('the store before family members: five blessings and a draft', (t) async {
    final store = await freshSeededStore();
    await store.create(Blessing(
      id: 'olddraft',
      title: 'Blessing',
      from: '',
      utc: DateTime.utc(2026, 11, 2, 3),
      utcOffset: const Duration(hours: -7),
      place: samplePlace,
      rawText: 'Words recorded before there were family members.',
      firstText: 'Words recorded before there were family members.',
      language: 'en',
      draft: true,
    ));
    expect(await store.list(), hasLength(6));
    debugPrint('SEEDED ${(await store.list()).length}');
    await store.close();
  });
}
DART
tool/sim_permissions.sh grant "$UDID" >/dev/null
( cd "$TMP/app" && timeout 900 flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/family_seed_test.dart --keep-app-running ) >"$TMP/seed.txt" 2>&1
grep -q "SEEDED 6" "$TMP/seed.txt" && grep -q "All tests passed" "$TMP/seed.txt" || { echo "== the $OLD app did not write its store"; tail -30 "$TMP/seed.txt"; exit 1; }
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
echo "== the app at $OLD wrote six blessings"
else
  timeout 300 xcrun simctl bootstatus "$UDID" -b >/dev/null || { echo "the simulator did not boot"; exit 1; }
  enrol 1
fi

# ---- 3. this build over it ----
timeout 900 flutter build ios --simulator --debug --dart-define=SPEECH_AUDIO="$AUDIO" >"$TMP/build.txt" 2>&1 || { echo "build failed"; tail -20 "$TMP/build.txt"; exit 1; }
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
if [[ "$START" == 1 ]]; then rm -f "$DATA/Documents/family_test_phase"; else echo "{\"phase\": $START}" >"$DATA/Documents/family_test_phase"; fi

setup() { # before phase $1
  case "$1" in
    4) xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLanguages -array es
       xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLocale es_US ;;
    5) xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLanguages 2>/dev/null || true
       xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLocale 2>/dev/null || true
       xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large ;;
  esac
  tool/sim_permissions.sh grant "$UDID" >/dev/null
  echo "== set up for phase $1"
}

answer() { # ACT what...
  case "$*" in
    "away "*)
      local s="${2:-65}"
      sleep 0.5; xcrun simctl launch "$UDID" com.apple.Preferences >/dev/null
      echo "== the app away for $s s"; sleep "$s"
      xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null; echo "== the app in front again" ;;
    "face match")
      # the lock asks as the locked sky appears; a second match, if it was not yet asking
      sleep 2; face match; sleep 4; face match; echo "== Face ID matched" ;;
    *) echo "== ACT not understood: $*" ;;
  esac
}

status=1
next=$START
for run in $(seq 1 7); do
  echo "== run $run, phase $next"
  setup "$next"
  rm -f "$TMP/done" "$TMP/failed" "$TMP/next"
  timeout "$LIMIT" flutter drive -d "$UDID" --driver=test_driver/integration_test.dart --target=integration_test/family_test.dart \
    --dart-define=SPEECH_AUDIO="$AUDIO" --keep-app-running 2>&1 |
    while IFS= read -r line; do
      echo "$line"
      case "$line" in
        "flutter: ACT "*) set -- ${line#flutter: ACT }; answer "$@" & ;;
        "flutter: NEXT "*) echo "${line#flutter: NEXT }" >"$TMP/next" ;;
        *"ALL DONE"*) touch "$TMP/done" ;;
        *"Some tests failed"*|*"[E]"*) touch "$TMP/failed" ;;
        *SIMSHOT*)
          name="${line##*SIMSHOT }"
          xcrun simctl io "$UDID" screenshot "$OUT_DIR/../$name.png" >/dev/null 2>&1 ;;
      esac
    done
  wait
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  if [[ -f "$TMP/failed" ]]; then echo "== phase $next FAILED"; break; fi
  if [[ -f "$TMP/done" ]]; then status=0; echo "== ALL PHASES PASSED"; break; fi
  if [[ ! -f "$TMP/next" ]]; then echo "== phase $next ended without NEXT"; break; fi
  next="$(cat "$TMP/next")"
  sleep 2
done
exit $status
