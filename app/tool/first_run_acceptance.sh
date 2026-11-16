#!/bin/bash
# The first run (lib/onboarding/), replayed on a simulator the way a person meets it: each case from
# a truly fresh install with its permissions reset, iOS's own questions answered by tool/alerts
# (never granted behind the app's back), the app's own buttons pressed by their VoiceOver labels.
#
#   tool/first_run_acceptance.sh [simulator udid] [case…]
#
# The permissions screen has an Allow on each row (the owner's ruling, 2026-11-16, second round):
# Continue is unavailable until the microphone and speech recognition are answered; location and
# Face ID may be left. Every case checks that no system question is up at rest, before an Allow.
#
# Cases (default: all of the iPhone ones, in this order):
#   allow     1: only the microphone and speech allowed, Continue unavailable until both are; the
#                rehearsal with the prepared English speech file through the real engine; the sky
#                is the Salt Lake Temple's; New blessing, Begin: no question; relaunch: the lock
#                asks for Face ID, then no first run
#   all       all four allowed in the order Face ID, location, speech, microphone: each row's own
#                question and no other; then through to the sky
#   mic       2: microphone refused: Off and Settings on its row, Continue once speech is answered,
#                no rehearsal, the recording screen's refused line
#   location  3: location refused: the row names the Salt Lake Temple; no place kept
#   kill      6 (and 4): killed with two rows answered, resumed with them shown answered; killed
#                mid-rehearsal and resumed; then Not now at the rehearsal: the sky, nothing kept
#   shared    7: first launch from a blessing file: read first, Keep asks Face ID; Not now keeps
#                nothing; the next launch offers the rest
#   seeded    8: the seeded build never sees any of it
#   big       11: Reduce Motion and the first accessibility text size
#   place     12: a file made by this build opens with its place; an old one still opens
#   icons     the three home-screen icons (light, dark, tinted)
#   ipad      10: case 1 on a stock iPad simulator, portrait and landscape (UDID in IPAD=…)
#   transitions  the opening paused while away; the moves between steps, filmed (not in the default)
#   spanish   9: case 1 on a temporary simulator set to Spanish (made here and deleted after)
#
# Screenshots (3x) and the film: ../design/sim/onboarding/. Results: RESULT lines, and
# ../design/sim/onboarding/results.txt. Every wait has a time limit.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
shift || true
CASES="${*:-allow all mic location kill shared big place seeded icons}"
BUNDLE=dev.summitstudio.uponThyHead
OUT="$(cd .. && pwd)/design/sim/onboarding"
PREFIX="${PREFIX:-}"
TMP="$(mktemp -d)"
TAP_DIR="$TMP/tapper"
DD="${TMPDIR:-/tmp}/uth_tapper_dd_$UDID"
FEED="$(pwd)/integration_test/audio/${FEED_LANG:-en}.m4a"
OLD_FILES="${OLD_FILES:-}" # a folder of .blessing files made before the place was added
mkdir -p "$OUT" "$TAP_DIR"
RESULTS="$OUT/results${PREFIX:+-$PREFIX}.txt"
: >"$RESULTS"

# the words pressed, in the phone's language (UI_LANG=es on a phone set to Spanish)
UI_LANG="${UI_LANG:-en}"
if [[ "$UI_LANG" == es ]]; then
  CONT=Continuar; ALLOW=Permitir; ONCE="Permitir una vez"; DONT="No permitir"; OKW=Aceptar
  TRYIT=Probar; NOTNOW="Ahora no"; NEWB="Nueva bendición"; MIC=Micrófono
  AL_mic="Permitir micrófono"; AL_speech="Permitir reconocimiento de voz"; AL_loc="Permitir ubicación"; AL_face="Permitir Face ID"
  ALLOWED=Permitido; OFFW=Desactivado; LOCKED=Bloqueado; SETMIC="Abrir Configuración para permitir micrófono"
else
  CONT=Continue; ALLOW=Allow; ONCE="Allow Once"; DONT="Don't Allow"; OKW=OK
  TRYIT="Try it"; NOTNOW="Not now"; NEWB="New blessing"; MIC=Microphone
  AL_mic="Allow microphone"; AL_speech="Allow speech recognition"; AL_loc="Allow location"; AL_face="Allow Face ID"
  ALLOWED=Allowed; OFFW=Off; LOCKED=Locked; SETMIC="Open Settings to allow microphone"
fi
# the words of each row's own iOS question, to tell which one came up
Q_mic='icrophone|icrófono'; Q_speech='peech|voz'; Q_loc='location|ubicación'

say() { echo "== $*"; }
result() { echo "RESULT $*" | tee -a "$RESULTS"; }
shot() { xcrun simctl io "$UDID" screenshot "$OUT/$PREFIX$1.png" >/dev/null 2>&1 && echo "   shot $PREFIX$1"; }

state="$(xcrun simctl list devices | grep "$UDID" || true)"
[[ "$state" == *Booted* ]] || { say "booting $UDID"; xcrun simctl boot "$UDID"; timeout 300 xcrun simctl bootstatus "$UDID" -b >/dev/null; }
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$UDID" content_size large || true
xcrun simctl location "$UDID" set 40.2338,-111.6585 # Provo: a place that is not the Salt Lake Temple's

# ---- the alert tapper ----
timeout 600 xcodebuild build-for-testing -project tool/alerts/Tapper.xcodeproj -scheme TapperUITests \
  -destination "id=$UDID" -derivedDataPath "$DD" >"$TMP/tapper_build.txt" 2>&1 || { echo "tapper build failed"; tail -20 "$TMP/tapper_build.txt"; exit 1; }
XCTESTRUN="$(ls "$DD"/Build/Products/*.xctestrun | head -1)"
TAPPER_PID=""
# A tapper's queries on the app hang for good once the app has been terminated and launched again
# by simctl (found 2026-11-16), so a fresh tapper is started before every launch.
start_tapper() {
  if [[ -n "$TAPPER_PID" ]]; then
    echo quit >"$TAP_DIR/cmd.tmp" && mv "$TAP_DIR/cmd.tmp" "$TAP_DIR/cmd"
    sleep 1; kill "$TAPPER_PID" 2>/dev/null; wait "$TAPPER_PID" 2>/dev/null
  fi
  rm -f "$TAP_DIR/ready" "$TAP_DIR/cmd" "$TAP_DIR/out"
  TEST_RUNNER_TAPPER_DIR="$TAP_DIR" TEST_RUNNER_RUN_SECONDS=1500 timeout 1600 \
    xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "id=$UDID" >"$TMP/tapper.txt" 2>&1 &
  TAPPER_PID=$!
  for _ in $(seq 1 180); do [[ -f "$TAP_DIR/ready" ]] && break; sleep 1; done
  [[ -f "$TAP_DIR/ready" ]] || { echo "tapper did not start"; tail -20 "$TMP/tapper.txt"; exit 1; }
}
start_tapper
tapper() {
  rm -f "$TAP_DIR/out"
  echo "$*" >"$TAP_DIR/cmd.tmp" && mv "$TAP_DIR/cmd.tmp" "$TAP_DIR/cmd"
  for _ in $(seq 1 120); do [[ -f "$TAP_DIR/out" ]] && break; sleep 0.25; done
  cat "$TAP_DIR/out" 2>/dev/null || echo "no answer"
}
FILM_PID=""
cleanup() {
  tapper quit >/dev/null; sleep 1; kill "$TAPPER_PID" 2>/dev/null
  [[ -n "$FILM_PID" ]] && kill -INT "$FILM_PID" 2>/dev/null
  xcrun simctl ui "$UDID" content_size large 2>/dev/null || true
  reduce_motion false
}
trap cleanup EXIT

app() { tapper "apptap $*"; }
sys() { tapper "tap $*"; }
labels() { tapper applabels; }
face() { xcrun simctl spawn "$UDID" notifyutil -p "com.apple.BiometricKit_Sim.pearl.$1"; }
enrol() { xcrun simctl spawn "$UDID" notifyutil -s com.apple.BiometricKit.enrollmentChanged "$1"; xcrun simctl spawn "$UDID" notifyutil -p com.apple.BiometricKit.enrollmentChanged; }
reduce_motion() { # true|false: Settings > Accessibility > Motion > Reduce Motion, for the whole simulator
  xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool "$1" 2>/dev/null
  xcrun simctl spawn "$UDID" notifyutil -p com.apple.accessibility.reduce.motion.status 2>/dev/null
}
# wait up to $2 s for a system question; prints its title and text
wait_alert() {
  local end=$((SECONDS + ${2:-20})) a
  while ((SECONDS < end)); do
    a="$(tapper alert)"
    [[ "$a" != none && "$a" != "no answer" ]] && { echo "$a"; return 0; }
    sleep 0.3
  done
  echo none
  return 1
}
# wait up to $2 s for the app to show a button or row labelled $1
wait_label() {
  local end=$((SECONDS + ${2:-20}))
  while ((SECONDS < end)); do
    [[ "$(labels)" == *"$1"* ]] && return 0
    sleep 0.4
  done
  return 1
}

TCC="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/TCC/TCC.db"
DATA=""
# a truly fresh install: the app and everything it had gone, every permission unanswered
fresh() {
  local build="$1" left
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
  xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null
  # A system question left up by an earlier run (an app killed while iOS was asking, or an
  # integration test's recording screen) can stay on screen through an uninstall and show over the
  # next install's opening (found 2026-11-16, c1-01 at 13:20). It belongs to the old install:
  # clear it here, so the guard over the opening sees only what the new install does.
  start_tapper
  left="$(tapper alert)"
  if [[ "$left" != none && "$left" != "no answer" ]]; then
    echo "   cleared a question left from before this install: ${left:0:90}"
    sys "Don't Allow" >/dev/null; sys "No permitir" >/dev/null; sleep 1
  fi
  xcrun simctl privacy "$UDID" reset all "$BUNDLE" 2>/dev/null
  sqlite3 "$TCC" "DELETE FROM access WHERE client = '$BUNDLE';"
  xcrun simctl spawn "$UDID" launchctl kill TERM system/com.apple.tccd 2>/dev/null
  # the per-app language a Spanish run writes outlives an uninstall: never inherit one
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" 2>/dev/null
  xcrun simctl install "$UDID" "$build"
  DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)" # it moves on each install
  mkdir -p "$DATA/tmp"
  cp "$FEED" "$DATA/tmp/feed.m4a"
  enrol 1
}
launch() { start_tapper; xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null; }
kill_app() { xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null; sleep 1; }
settings() { cat "$DATA/Library/Application Support/settings.json" 2>/dev/null || echo '{}'; }
setting() { settings | python3 -c 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print("" if v is None else v)' "$1"; }
stored() { sqlite3 "$DATA/Documents/blessings.sqlite" "SELECT count(*) FROM blessings;" 2>/dev/null || echo 0; }
audio_files() { ls "$DATA/Library/Application Support/audio" 2>/dev/null | wc -l | tr -d ' '; }
practice_files() { ls "$DATA/tmp/practice" 2>/dev/null | wc -l | tr -d ' '; }
tcc() { sqlite3 "$TCC" "SELECT service || '=' || auth_value FROM access WHERE client = '$BUNDLE' ORDER BY service;" | tr '\n' ' '; }
check() { # name, condition result (0 = pass), detail
  if [[ "$2" == 0 ]]; then result "$1 PASS ${3:-}"; else result "$1 FAIL ${3:-}"; fi
}

# ---- builds ----
say "building (first run, with the prepared speech file for the rehearsal)"
timeout 900 flutter build ios --simulator --debug --dart-define=FIRST_RUN_FEED=feed.m4a >"$TMP/build.txt" 2>&1 || { echo "build failed"; tail -20 "$TMP/build.txt"; exit 1; }
APP_FR="$TMP/first_run/Runner.app"
mkdir -p "$TMP/first_run" && cp -R build/ios/iphonesimulator/Runner.app "$APP_FR"

# Through the opening and the welcome to the permissions screen. $1: shot prefix ("" for none).
to_permissions() {
  local s="$1" end a l
  launch
  # No system question may be on screen before Continue on the permissions screen (the owner's
  # ruling, 2026-11-16). Watched the whole way through the opening and the welcome, not sampled.
  NO_ALERT=0; ALERT_SEEN=""
  guard() { a="$(tapper alert)"; if [[ "$a" != none && "$a" != "no answer" ]]; then NO_ALERT=1; ALERT_SEEN="$a"; fi; }
  if [[ -n "$s" ]]; then
    sleep 1.3; guard; shot "${s}01-opening-rising"
    sleep 2.0; guard; shot "${s}02-opening"
  fi
  # the welcome: Continue, and none of the permission rows yet
  end=$((SECONDS + 25))
  while ((SECONDS < end)); do
    guard
    l="$(tapper appall)"
    [[ "$l" == *"$CONT"* && "$l" != *"$MIC"* ]] && break
    sleep 0.4
  done
  [[ "$l" == *"$CONT"* && "$l" != *"$MIC"* ]] || { result "${PREFIX}${s} welcome FAIL no welcome: ${l:0:160}"; return 1; }
  sleep 1.2; guard
  l="$(tapper appall)"
  [[ "$l" != *"$MIC"* ]] || { result "${PREFIX}${s} welcome FAIL the permissions screen came before the shot"; return 1; }
  [[ -n "$s" ]] && shot "${s}03-welcome"
  check "${PREFIX}${s:-c?-}no system question during the opening or the welcome" "$NO_ALERT" "${ALERT_SEEN:0:120}"
  ((NO_ALERT == 0)) || return 1
  app "$CONT" >/dev/null
  # the permissions screen: its rows, with nothing asked and nothing ticked yet
  end=$((SECONDS + 15))
  while ((SECONDS < end)); do l="$(tapper appall)"; [[ "$l" == *"$MIC"* ]] && break; sleep 0.4; done
  [[ "$l" == *"$MIC"* ]] || { result "${PREFIX}${s} permissions FAIL rows not shown: ${l:0:160}"; return 1; }
  # at rest: watched for three seconds, no question up, and Continue unavailable
  NO_ALERT=0; ALERT_SEEN=""
  for _ in 1 2 3 4 5 6; do guard; sleep 0.5; done
  check "${PREFIX}${s:-c?-}at rest on the permissions screen: no system question" "$NO_ALERT" "${ALERT_SEEN:0:120}"
  ((NO_ALERT == 0)) || return 1
  check "${PREFIX}${s:-c?-}at rest: Continue unavailable" "$([[ "$(tapper "appenabled $CONT")" == no ]]; echo $?)" "($(tapper "appenabled $CONT"))"
  [[ -n "$s" ]] && shot "${s}04-permissions"
  return 0
}

# A row's own Allow, and its question answered. $1: mic|speech|loc|face; $2: the answer ("Allow",
# "Don't Allow", "Allow Once"; Face ID's scan is matched); $3: a shot's name while the question is
# up ("" for none). Checks the question was that row's, and that no other followed.
allow_row() {
  local which="$1" ans="$2" s="${3:-}" label a r q
  label="AL_$which"; label="${!label}"
  a="$(tapper alert)"
  [[ "$a" == none ]] || { result "${PREFIX}allow $which FAIL a question was already up: ${a:0:100}"; return 1; }
  if [[ "$which" == face && "$(tapper applabels)" != *"$label"* ]]; then
    # The lock row asks nothing on this device: Touch ID has no question (a tick from the start),
    # and with no Face ID enrolled the row is "App lock", the passcode (the simulator's enrolment
    # does not always hold across installs, seen 2026-11-16). Nothing to press.
    result "${PREFIX}allow face: nothing to ask here (Touch ID, or no Face ID enrolled): the lock row has no Allow"
    return 0
  fi
  r="$(app "$label")"
  [[ "$r" == ok* ]] || { result "${PREFIX}allow $which FAIL $r"; return 1; }
  if [[ "$which" == face ]]; then
    # A phone asks "Do you want to allow … to use Face ID?" once; this simulator never does and goes
    # straight to the scan (found 2026-11-16). Either way the scan is matched.
    a="$(wait_alert 4)"
    sleep 0.5; [[ -n "$s" ]] && shot "$s"
    if [[ "$a" != none ]]; then sys "$OKW" >/dev/null; sleep 1.2; fi
    face match
    result "${PREFIX}allow face: $([[ "$a" == none ]] && echo 'scan only, no consent question (simulator)' || echo "question: ${a:0:80}")"
  else
    a="$(wait_alert 15)" || { result "${PREFIX}allow $which FAIL no question came up"; return 1; }
    q="Q_$which"
    check "${PREFIX}allow $which: its own question" "$([[ "$a" =~ ${!q} ]]; echo $?)" "(${a:0:90})"
    sleep 0.6; [[ -n "$s" ]] && shot "$s"
    sys "$ans" >/dev/null
  fi
  sleep 1.5
  a="$(tapper alert)"
  check "${PREFIX}allow $which: no other question after it" "$([[ "$a" == none ]]; echo $?)" "(${a:0:90})"
  return 0
}
cont_state() { tapper "appenabled $CONT"; }

case_allow() {
  local lang="$UI_LANG" l
  say "case 1: the microphone and speech allowed; location and Face ID left"
  fresh "$APP_FR"
  to_permissions "" || return
  shot "01-rest"
  allow_row mic "$ALLOW" "02-asking" || return
  sleep 0.5; l="$(tapper appall)"
  check "${PREFIX}case1 after the microphone: Continue still unavailable, speech named as needed" "$([[ "$(cont_state)" == no && "$l" == *"$([[ $lang == es ]] && echo 'reconocimiento de voz para seguir' || echo 'Allow speech recognition to go on')"* ]]; echo $?)" "($(cont_state))"
  allow_row speech "$ALLOW" "" || return
  sleep 0.5
  check "${PREFIX}case1 both required answered: Continue available" "$([[ "$(cont_state)" == yes ]]; echo $?)" "($(cont_state))"
  shot "03-required-answered"
  app "$CONT" >/dev/null
  local tryit="$TRYIT"
  wait_label "$tryit" 15 || { result "${PREFIX}case1 rehearsal FAIL: $(labels)"; return; }
  result "${PREFIX}case1 the rehearsal offered PASS"
  sleep 1; shot "c1-13-rehearsal"
  app "$tryit" >/dev/null
  sleep 2.2
  local begin="Begin. Nothing is recorded until you press"; [[ "$lang" == es ]] && begin="$(beginlabel_es)"
  app "$begin" >/dev/null
  sleep 4
  local amen="Amen. Hold to finish"; [[ "$lang" == es ]] && amen="$(amenlabel_es)"
  tapper "apphold 1.6 $amen" >/dev/null
  local cont="$CONT"
  local end=$((SECONDS + 60))
  while ((SECONDS < end)); do [[ "$(labels)" == *"$cont"* ]] && break; sleep 1; done
  sleep 2; shot "c1-17-practice-written"
  check "${PREFIX}case1 practice nothing kept" "$([[ "$(stored)" == 0 && "$(audio_files)" == 0 && "$(practice_files)" == 0 ]]; echo $?)" "store=$(stored) audio=$(audio_files) practice=$(practice_files)"
  app "$cont" >/dev/null
  sleep 3; shot "c1-18-sky"
  check "${PREFIX}case1 done; the Salt Lake Temple's sky (no place, location never asked)" "$([[ "$(setting firstRun)" == done && -z "$(setting place)" && -z "$(setting locationAsked)" && "$(tcc)" != *Location* ]]; echo $?)" "firstRun=$(setting firstRun) place='$(setting place)' locationAsked='$(setting locationAsked)' tcc: $(tcc)"
  check "${PREFIX}case1 Face ID not asked in the first run" "$([[ -z "$(setting faceIdAsked)" ]]; echo $?)" "faceIdAsked='$(setting faceIdAsked)'"
  local newb="$NEWB"
  app "$newb" >/dev/null
  sleep 3
  local q1; q1="$(tapper alert)"
  app "$begin" >/dev/null
  sleep 3
  local q2; q2="$(tapper alert)"
  local d; d="$(tapper "apphold 1.6 $(discardlabel)")"; sleep 2
  local after; after="$(labels)"
  check "${PREFIX}case1 New blessing, Begin: no system question" "$([[ "$q1" == none && "$q2" == none ]]; echo $?)" "($q1 / $q2)"
  check "${PREFIX}case1 the test recording discarded (back to Begin)" "$([[ "$after" == *"$begin"* ]]; echo $?)" "hold: ${d:0:60}; labels: ${after:0:120}"
  kill_app
  # the next lock: the app locks at launch and asks the phone (Face ID's question on a phone; on
  # this simulator straight to the scan)
  launch
  sleep 2.5
  local lk; lk="$(tapper appall)"; local qa; qa="$(tapper alert)"
  shot "c1-19-relaunch-locked"
  face match; sleep 3
  shot "c1-20-relaunch"
  l="$(tapper appall)"
  check "${PREFIX}case1 relaunch: locked, Face ID asked, unlocked by the face" "$([[ "$lk" == *"$LOCKED"* && "$l" != *"$LOCKED"* ]]; echo $?)" "before: ${lk:0:80}; question: ${qa:0:60}"
  check "${PREFIX}case1 relaunch: no first run" "$([[ "$l" != "no answer" && "$l" != *"$cont"* && "$l" != *"$MIC"* && "$l" != *"$(keptlabel)"* && "$(setting firstRun)" == done ]]; echo $?)" "labels: ${l:0:160}"
}

case_all() {
  local l
  say "all four allowed: Face ID, location, speech, microphone"
  fresh "$APP_FR"
  to_permissions "" || return
  allow_row face "$OKW" "" || return
  check "${PREFIX}all Continue unavailable after Face ID alone" "$([[ "$(cont_state)" == no ]]; echo $?)"
  allow_row loc "$ONCE" "02b-asking-location" || return
  allow_row speech "$ALLOW" "" || return
  check "${PREFIX}all Continue still unavailable before the microphone" "$([[ "$(cont_state)" == no ]]; echo $?)"
  allow_row mic "$ALLOW" "" || return
  sleep 0.5; shot "04-all-answered"
  l="$(tapper appall)"
  check "${PREFIX}all every row shown allowed, no Allow left" "$([[ "$(grep -o "$ALLOWED" <<<"$l" | wc -l | tr -d ' ')" -ge 4 && "$l" != *"$AL_mic"* && "$l" != *"$AL_face"* ]]; echo $?)" "${l:0:200}"
  app "$CONT" >/dev/null
  wait_label "$TRYIT" 15
  app "$NOTNOW" >/dev/null
  wait_label "$NEWB" 15; sleep 1.5
  shot "all-sky"
  check "${PREFIX}all through to the sky, the place kept" "$([[ "$(setting firstRun)" == done && -n "$(setting place)" && "$(setting faceIdAsked)" == True ]]; echo $?)" "place=$(setting place) faceIdAsked=$(setting faceIdAsked) tcc: $(tcc)"
}
keptlabel() { [[ "$UI_LANG" == es ]] && echo "Se guardó una grabación" || echo "A recording was kept"; }
discardlabel() { python3 -c "import re,sys;s=open('lib/strings.dart').read();i=s.index('class _Spanish') if sys.argv[1]=='es' else 0;m=re.search(r\"discardLabel => '([^']*)'\",s[i:]);print(m.group(1))" "$UI_LANG"; }
beginlabel_es() { python3 -c "import re;s=open('lib/strings.dart').read();i=s.index('class _Spanish');m=re.search(r\"beginLabel => '([^']*)'\",s[i:]);print(m.group(1))"; }
amenlabel_es() { python3 -c "import re;s=open('lib/strings.dart').read();i=s.index('class _Spanish');m=re.search(r\"amenLabel => '([^']*)'\",s[i:]);print(m.group(1))"; }

case_mic() {
  local l
  say "case 2: microphone refused"
  fresh "$APP_FR"
  to_permissions "" || return
  allow_row mic "$DONT" "" || return
  sleep 0.5; l="$(tapper appall)"
  check "${PREFIX}case2 the refused row: Off and Settings, Continue still unavailable" "$([[ "$l" == *"$OFFW"* && "$l" == *"$SETMIC"* && "$(cont_state)" == no ]]; echo $?)" "${l:0:200}"
  allow_row speech "$ALLOW" "" || return
  sleep 0.5
  check "${PREFIX}case2 Continue available once speech is answered" "$([[ "$(cont_state)" == yes ]]; echo $?)"
  shot "05-refused"
  app "$CONT" >/dev/null
  wait_label "$NEWB" 15
  sleep 1.5
  l="$(labels)"
  check "${PREFIX}case2 no rehearsal offered" "$([[ "$l" != *"$TRYIT"* && "$l" == *"$NEWB"* ]]; echo $?)" "firstRun=$(setting firstRun)"
  app "$NEWB" >/dev/null
  sleep 3
  local q; q="$(tapper alert)"
  shot "c2-12-recording-refused"
  l="$(labels)"
  local opens="Open Settings"; [[ "$UI_LANG" == es ]] && opens="Abrir Configuración"
  check "${PREFIX}case2 recording screen: turned-off line, Open Settings, no question" "$([[ "$l" == *"$opens"* && "$q" == none ]]; echo $?)" "alert=$q"
}

case_location() {
  say "case 3: location refused"
  fresh "$APP_FR"
  to_permissions "" || return
  allow_row loc "$DONT" "" || return
  sleep 0.6; shot "c3-10-location-refused"
  check "${PREFIX}case3 the row names the Salt Lake Temple" "$([[ "$(tapper appall)" == *"Salt Lake Temple will be used"* ]]; echo $?)"
  allow_row mic Allow "" || return
  allow_row speech Allow "" || return
  app "$CONT" >/dev/null
  wait_label "Try it" 15
  app "Not now" >/dev/null
  wait_label "New blessing" 15; sleep 1.5
  shot "c3-11-sky"
  check "case3 no place kept (the Salt Lake Temple is used)" "$([[ -z "$(setting place)" && "$(setting locationAsked)" == True ]]; echo $?)" "place='$(setting place)' tcc: $(tcc)"
}

case_kill() {
  say "case 6: killed with two rows answered, then mid-rehearsal; case 4: Not now at the rehearsal"
  fresh "$APP_FR"
  to_permissions "" || return
  allow_row mic Allow "" || return
  allow_row loc "Allow Once" "" || return
  shot "c6-01-two-answered-then-killed"
  kill_app
  check "case6 killed on the permissions screen: kept at the permissions step" "$([[ "$(setting firstRun)" == permissions ]]; echo $?)" "firstRun=$(setting firstRun)"
  launch
  wait_label "$AL_speech" 20; sleep 1.5
  shot "c6-02-resumed-permissions"
  local l; l="$(tapper appall)"
  check "case6 resumed on the permissions screen with the microphone and location answered" "$([[ "$l" == *"Microphone. Required. To hear the blessing as it is given. Allowed"* && "$l" == *"Location. Optional"*"Allowed"* && "$l" != *"$AL_mic"* && "$l" != *"$AL_loc"* && "$l" == *"$AL_speech"* ]]; echo $?)" "${l:0:400}"
  check "case6 nothing asked on resuming" "$([[ "$(tapper alert)" == none ]]; echo $?)"
  allow_row speech Allow "" || return
  app Continue >/dev/null
  wait_label "Try it" 15
  app "Try it" >/dev/null
  sleep 2; app "Begin. Nothing is recorded until you press" >/dev/null
  sleep 3; shot "c6-03-practice-then-killed"
  kill_app
  check "case6 killed mid-rehearsal: nothing kept" "$([[ "$(stored)" == 0 && "$(audio_files)" == 0 ]]; echo $?)" "store=$(stored) audio=$(audio_files) practice=$(practice_files) firstRun=$(setting firstRun)"
  launch
  wait_label "Try it" 20; sleep 1.5
  shot "c6-04-resumed-rehearsal"
  check "case6 resumed at the rehearsal's question; the practice's file gone" "$([[ "$(labels)" == *"Try it"* && "$(practice_files)" == 0 ]]; echo $?)"
  # case 4
  app "Not now" >/dev/null
  wait_label "New blessing" 15; sleep 1.5
  shot "c4-01-not-now-sky"
  check "case4 Not now: straight to the sky, nothing kept" "$([[ "$(stored)" == 0 && "$(audio_files)" == 0 && "$(setting firstRun)" == done ]]; echo $?)" "store=$(stored) audio=$(audio_files)"
}

SHARED_FILE="${SHARED_FILE:-}"
urlfor() { python3 -c 'import sys, urllib.parse; print("file://" + urllib.parse.quote(sys.argv[1]))' "$1"; }
case_shared() {
  say "case 7: first launch from a blessing file"
  [[ -f "$SHARED_FILE" ]] || { result "case7 SKIP no SHARED_FILE"; return; }
  fresh "$APP_FR"
  start_tapper
  xcrun simctl openurl "$UDID" "$(urlfor "$SHARED_FILE")"
  sleep 2.5; shot "c7-01-opening"
  wait_label Continue 20; sleep 1.2
  shot "c7-02-shared-line"
  app Continue >/dev/null
  wait_label Keep 10; sleep 1.2
  shot "c7-03-read-first"
  check "case7 readable with no Face ID, no question" "$([[ "$(tapper alert)" == none && "$(stored)" == 0 ]]; echo $?)"
  app Keep >/dev/null
  local a; a="$(wait_alert 5)"
  echo "   on Keep: $a"
  sleep 0.5; shot "c7-04-keep-face-id"
  [[ "$a" != none ]] && { sys OK >/dev/null; sleep 1.2; }
  face match
  sleep 3; shot "c7-05-kept-reading"
  check "case7 Keep: Face ID asked, then saved" "$([[ "$(stored)" == 1 ]]; echo $?)" "store=$(stored) firstRun=$(setting firstRun) tcc: $(tcc)"
  check "case7 nothing else asked" "$([[ "$(tcc)" != *Microphone* && "$(tcc)" != *Speech* ]]; echo $?)" "tcc: $(tcc)"
  kill_app
  launch
  sleep 2; face match
  wait_label Continue 20; sleep 1.5
  shot "c7-06-next-launch-rest"
  check "case7 next launch: the rest offered (permissions)" "$([[ "$(labels)" == *Microphone* || "$(labels)" == *Continue* ]]; echo $?)"
  say "case 7, second run: Not now"
  fresh "$APP_FR"
  start_tapper
  xcrun simctl openurl "$UDID" "$(urlfor "$SHARED_FILE")"
  wait_label Continue 20; app Continue >/dev/null
  wait_label "Not now" 10; sleep 1
  app "Not now" >/dev/null
  wait_label "New blessing" 15; sleep 1.5
  shot "c7-07-not-now-sky"
  check "case7 Not now: nothing saved, no question" "$([[ "$(stored)" == 0 && "$(tcc)" == "" ]]; echo $?)" "store=$(stored) tcc: $(tcc) firstRun=$(setting firstRun)"
  kill_app; launch
  wait_label Continue 20; sleep 1.5
  shot "c7-08-next-launch-rest"
  check "case7 next launch after Not now: the rest offered" "$([[ "$(labels)" == *Continue* ]]; echo $?)"
}

case_big() {
  say "case 11: Reduce Motion and the first accessibility text size"
  fresh "$APP_FR"
  reduce_motion true
  xcrun simctl ui "$UDID" content_size accessibility-medium
  launch
  sleep 1.5; shot "big-01-opening"
  wait_label Continue 20; sleep 1.2; shot "big-02-welcome"
  app Continue >/dev/null; sleep 1.5; shot "big-03-permissions"
  check "${PREFIX}case11 at rest: no question" "$([[ "$(tapper alert)" == none ]]; echo $?)"
  # the rows and Continue run past the screen at this size: the page scrolls to them, as a person
  # would, once the microphone's row (at the top) is answered
  allow_row mic "Don't Allow" "" >/dev/null
  tapper appswipeup >/dev/null
  sleep 1; shot "big-04-permissions-scrolled"
  allow_row speech Allow "" >/dev/null
  allow_row loc "Don't Allow" "" >/dev/null
  sleep 0.5; shot "big-05-permissions-answered"
  tapper appswipeup >/dev/null; sleep 1; shot "big-06-permissions-answered-scrolled"
  app Continue >/dev/null
  sleep 2
  check "${PREFIX}case11 the Allows reachable and Continue after them, at accessibility-medium with Reduce Motion" "$([[ "$(setting firstRun)" == done ]]; echo $?)" "firstRun=$(setting firstRun) tcc: $(tcc)"
  wait_label "New blessing" 15; sleep 1.5; shot "big-12-sky"
  reduce_motion false
  xcrun simctl ui "$UDID" content_size large
}

case_seeded() {
  say "case 8: the seeded build"
  timeout 900 flutter build ios --simulator --debug --dart-define=SEED_SAMPLES=true >"$TMP/build_seeded.txt" 2>&1 || { result "case8 FAIL build"; return; }
  fresh build/ios/iphonesimulator/Runner.app
  launch
  sleep 3; face match; sleep 3
  shot "c8-01-seeded"
  check "case8 seeded build: no first run" "$([[ "$(setting firstRun)" == existing && "$(labels)" != *Continue* ]]; echo $?)" "firstRun=$(setting firstRun) store=$(stored)"
}

case_place() {
  say "case 12: files with and without the place"
  local new="${NEW_FILE:-}" old
  old="$(ls "$OLD_FILES"/*.blessing 2>/dev/null | grep -i 'an old file' | head -1)"
  [[ -f "$new" && -f "$old" ]] || { result "case12 SKIP NEW_FILE/OLD_FILES"; return; }
  grep -q '"place"' "$new" && result "case12 the new build's file carries the place PASS $(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("place"))' "$new")" || result "case12 the new build's file carries the place FAIL"
  # an install through its first run, then each file opened as iOS delivers it
  timeout 900 flutter build ios --simulator --debug --dart-define=SEED_SAMPLES=true >"$TMP/build_seeded.txt" 2>&1 || { result "case12 FAIL build"; return; }
  fresh build/ios/iphonesimulator/Runner.app
  # the receiver is somewhere else: San Francisco
  xcrun simctl location "$UDID" set 37.7749,-122.4194
  launch; sleep 3; face match; sleep 2
  for f in "$new" "$old"; do
    xcrun simctl openurl "$UDID" "$(urlfor "$f")"
    sleep 1.5; face match
    # the second file's sheet rises over the first one's reading page, a few seconds later
    wait_label Keep 20 && { sleep 1; [[ "$f" == "$old" ]] && shot "c12-01-old-file-opened"; app Keep >/dev/null; }
    sleep 2
    [[ "$(labels)" == *"Keep"* ]] && { app Keep >/dev/null; sleep 2; }
  done
  shot "c12-02-both-kept"
  local rows
  rows="$(sqlite3 "$DATA/Documents/blessings.sqlite" "SELECT title || ' @ ' || latitude || ',' || longitude FROM blessings WHERE title IN ('A short one', 'An old file, before the place');" 2>&1 | tr '\n' ';')"
  echo "   $rows"
  check "case12 the new file at its own place, the old one opened" "$([[ "$rows" == *"A short one @ 40.2,-111.7"* && "$rows" == *"An old file"* ]]; echo $?)" "stored: $rows; receiver's settings place: $(setting place)"
  xcrun simctl location "$UDID" set 40.2338,-111.6585
}

case_icons() {
  say "icons: light, dark, tinted on the home screen"
  tapper home >/dev/null; sleep 1
  for mode in light dark; do
    xcrun simctl ui "$UDID" appearance "$mode"; sleep 2
    shot "icons-$mode"
  done
  xcrun simctl ui "$UDID" appearance light
  # tinted: the home screen's Edit > Customize > Tinted, as a person sets it; then back to Default
  icon_style() {
    tapper sbhold >/dev/null; sleep 1
    tapper "sbtap Edit" >/dev/null; sleep 1
    tapper "sbtap Customize" >/dev/null; sleep 1.5
    tapper "sbtap $1" >/dev/null; sleep 1.5
    tapper "sbtap dismiss popup" >/dev/null; sleep 1
    tapper "sbtap Done" >/dev/null; sleep 1.5
  }
  icon_style Tinted
  shot "icons-tinted"
  icon_style Default
}

# 9: case 1 on a phone set to Spanish, so iOS's own questions are Spanish too. A temporary simulator
# is made for it and deleted after, so no simulator is left in Spanish.
case_spanish() {
  say "case 9: Spanish, on a temporary simulator"
  local es
  es="$(xcrun simctl create "UTH first run Spanish (temporary)" "iPhone 17 Pro")" || { result "case9 FAIL create"; return; }
  xcrun simctl boot "$es"; timeout 300 xcrun simctl bootstatus "$es" -b >/dev/null
  xcrun simctl spawn "$es" defaults write -g AppleLanguages -array es-US es
  xcrun simctl spawn "$es" defaults write -g AppleLocale es_US
  xcrun simctl shutdown "$es"; xcrun simctl boot "$es"; timeout 300 xcrun simctl bootstatus "$es" -b >/dev/null
  echo "   the phone's languages: $(xcrun simctl spawn "$es" defaults read -g AppleLanguages | tr -d ' \n')"
  UI_LANG=es PREFIX="${PREFIX}es-" FEED_LANG=es timeout 1500 "$0" "$es" allow mic
  cat "$OUT/results-${PREFIX}es-.txt" >>"$RESULTS" 2>/dev/null
  xcrun simctl shutdown "$es" 2>/dev/null
  xcrun simctl delete "$es" && echo "   deleted the temporary simulator $es"
}

# 10: on a stock iPad, portrait then landscape. IPAD: its UDID (an existing simulator; nothing is made).
case_ipad() {
  local ipad="${IPAD:-6FF8A689-6647-4A0D-8226-4F1F4BC3496D}"
  say "case 10: iPad $ipad"
  PREFIX="${PREFIX}ipad-" timeout 1500 "$0" "$ipad" ipadrun
  cat "$OUT/results-${PREFIX}ipad-.txt" >>"$RESULTS" 2>/dev/null
  xcrun simctl shutdown "$ipad" 2>/dev/null
}
case_ipadrun() {
  fresh "$APP_FR"
  tapper "orient portrait" >/dev/null
  to_permissions "p-" || return
  tapper "orient landscape" >/dev/null; sleep 2
  shot "l-04-permissions"
  allow_row mic "$ALLOW" "" || return
  allow_row loc "$ONCE" "" || return
  tapper "orient portrait" >/dev/null; sleep 2
  shot "p-05-two-answered"
  allow_row speech "$ALLOW" "" || return
  allow_row face "$OKW" "" || return
  tapper "orient landscape" >/dev/null; sleep 2
  shot "l-12-permissions-answered"
  app "$CONT" >/dev/null
  wait_label "$TRYIT" 15; sleep 1; shot "l-13-rehearsal"
  tapper "orient portrait" >/dev/null; sleep 2; shot "p-13-rehearsal"
  app "$TRYIT" >/dev/null; sleep 2.5; shot "p-14-practice"
  tapper "orient landscape" >/dev/null; sleep 2; shot "l-14-practice"
  app "$NOTNOW" >/dev/null; sleep 2
  wait_label "$NEWB" 15; sleep 1.5; shot "l-18-sky"
  tapper "orient portrait" >/dev/null; sleep 2; shot "p-18-sky"
  check "case10 iPad: through to the sky, nothing kept" "$([[ "$(setting firstRun)" == done && "$(stored)" == 0 ]]; echo $?)" "firstRun=$(setting firstRun)"
}

# The steps' moves (the owner's addition, 2026-11-16), filmed: the opening is interrupted by the app
# switcher for six seconds (longer than the opening itself) and must still be there, the name not
# yet arrived and no welcome, when the app comes back; then the name, the soft hand-over to the
# welcome, Continue (the welcome leaves left, the permissions arrive from the right), both required
# rows, Continue (on to the rehearsal's question). Film: p2-transitions.mov; frame strips of each
# move: transitions-*.png, made from the film with tool/frame_strip.sh.
now() { python3 -c 'import time; print(f"{time.time():.3f}")'; }
case_transitions() {
  local raw="$TMP/transitions.mp4" t0 t_open t_back t_cont1 t_cont2 l
  say "transitions: the opening paused while away, the welcome's hand-over, the two moves"
  fresh "$APP_FR"
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$raw" >/dev/null 2>&1 &
  FILM_PID=$!
  sleep 1.5; t0="$(now)"
  launch
  sleep 1.0
  tapper switcher >/dev/null; t_away="$(now)"
  shot "t-01-away"
  sleep 6
  tapper "open $BUNDLE" >/dev/null; t_back="$(now)"
  sleep 0.4
  l="$(tapper appall)"
  shot "t-02-back"
  check "${PREFIX}transitions: back after six seconds away, still the opening (no welcome)" "$([[ "$l" != *"$CONT"* ]]; echo $?)" "(${l:0:120})"
  sleep 2.6; shot "t-03-name"
  l="$(tapper appall)"
  check "${PREFIX}transitions: the opening still there 3 s after coming back" "$([[ "$l" != *"$CONT"* ]]; echo $?)" "(${l:0:120})"
  wait_label "$CONT" 15 || { result "${PREFIX}transitions FAIL no welcome"; }
  t_welcome="$(now)"
  sleep 4.5; shot "t-04-welcome"
  t_cont1="$(now)"; app "$CONT" >/dev/null
  wait_label "$AL_mic" 10
  sleep 1.5
  allow_row mic "$ALLOW" ""
  allow_row speech "$ALLOW" ""
  sleep 1
  t_cont2="$(now)"; app "$CONT" >/dev/null
  wait_label "$TRYIT" 10; sleep 2
  kill -INT "$FILM_PID" 2>/dev/null; wait "$FILM_PID" 2>/dev/null; FILM_PID=""
  xcrun simctl status_bar "$UDID" clear 2>/dev/null
  local mov="$OUT/${PREFIX}transitions.mov" vstart
  ffmpeg -y -loglevel error -i "$raw" -vf "scale=804:-2" -c:v libx264 -pix_fmt yuv420p -crf 20 "$mov" && echo "   film ${PREFIX}transitions.mov"
  # Frame strips: the times printed here are only near the moves (the film's start and the taps'
  # own delay are not exact); read each move's start off the film and make its strip with
  # tool/frame_strip.sh (p2-transitions-*.png were made that way, 40 to 100 ms a frame).
  vstart="$(python3 -c "print($t0 - 1.5)")"
  echo "   about: away $(python3 -c "print(f'{$t_away-$vstart:.1f}')") back $(python3 -c "print(f'{$t_back-$vstart:.1f}')") welcome $(python3 -c "print(f'{$t_welcome-$vstart:.1f}')") continue $(python3 -c "print(f'{$t_cont1-$vstart:.1f}')") continue $(python3 -c "print(f'{$t_cont2-$vstart:.1f}')") (s into the film)"
  kill_app
}

# close-up of the four rows at rest (shot 01-rest of case 1); and beside it the first round's
# (icons-closeup.png, made before this round)
case_permsclose() {
  local f="$OUT/${PREFIX}01-rest.png" before="$OUT/icons-closeup.png"
  [[ -f "$f" ]] || return
  magick "$f" -crop "1206x${CLOSE_H:-1120}+0+${CLOSE_Y:-1090}" +repage "$OUT/${PREFIX}icons-after.png" 2>/dev/null && echo "   shot ${PREFIX}icons-after"
  [[ -f "$before" ]] && magick "$before" -background black -gravity north -extent "1206x${CLOSE_H:-1120}" "$OUT/${PREFIX}icons-after.png" +append "$OUT/${PREFIX}icons-before-after.png" 2>/dev/null && echo "   shot ${PREFIX}icons-before-after"
}

for c in $CASES; do
  "case_$c"
done
say "done"
cat "$RESULTS"
