#!/bin/bash
# Sending a blessing by link, receiving one, and passing a blessing along
# (integration_test/link_acceptance_test.dart), on the simulator, against the website running here.
#
#   tool/link_acceptance.sh [simulator udid] [ipad]
#
# Starts the website (../website, `pnpm start` on 4319, links kept in a new temporary folder) and
# tool/link_proxy.py on 4320 in front of it; the app is built with LINK_SERVICE=http://127.0.0.1:4320,
# so every request it makes is written down. Web pages are opened in Chrome (tool/link_web.mjs).
# Links reach the app through `simctl openurl uponthyhead-test://b/<id>#<key>` (debug builds only).
#
# Phases, each a new launch:
#   1  launched here: three blessings sent by link, the web pages checked; deleted from the store
#   2  launched by a link, locked: the keep sheet; the ways in; Your links, Stop; delete; refusals;
#      no internet (the website stopped)
#   3  passing it along (the prepared speech file)
#   4  Spanish
#   5  English at the first accessibility text size
# With `ipad`: phase 1 (one link), then 6, launched by the link.
# At the end: every request the app made is checked for keys and stop tokens. Screenshots land in
# ../design/sim/link/. Every phase has a time limit. The website and proxy are stopped on exit and
# the app's language and the text size are put back.
set -uo pipefail
RESUME="${RESUME:-}"
cd "$(dirname "$0")/.."
UDID="${1:-512A6D6E-FE1E-43AF-AB3F-53C0DFE04208}"
MODE="${2:-phone}"
BUNDLE=dev.summitstudio.uponThyHead
OUT_DIR="$(cd .. && pwd)/design/sim/link"
WEBSITE="$(cd ../website && pwd)"
LIMIT="${LIMIT:-900}" # seconds per phase
TAP_DIR="${TMPDIR:-/tmp}/uth_tapper"
DD="${TMPDIR:-/tmp}/uth_tapper_dd"
TMP="$(mktemp -d)"
LINKS="${LINKS_DIR:-$TMP/links}" # the website's locked copies
# RESUME=<phase>: start there, keeping the app's data and the test's state from the last run (with
# LINKS_DIR=<that run's links folder>, so the links it made still open)

FIX="$TMP/files"     # files the share sheet held
REQ="$TMP/requests.jsonl"
AUDIO="$PWD/integration_test/audio"
mkdir -p "$OUT_DIR" "$FIX" "$LINKS"
if [[ "$MODE" == ipad ]]; then rm -f "$OUT_DIR"/[0-9][0-9]-ipad-*.png; PHASES="1 6"; else [[ -z "$RESUME" ]] && rm -f "$OUT_DIR"/[0-9][0-9]-[el]*.png; PHASES="${PHASES:-1 2 3 4 5}"; fi

state="$(xcrun simctl list devices | grep "$UDID" || true)"
[[ "$state" == *Booted* ]] || { echo "booting the simulator"; xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID" -b >/dev/null; }
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$UDID" content_size large || true

# ---- the website and the proxy ----
WEB_PID=""
PROXY_PID=""
web_up() { curl -s -o /dev/null --max-time 2 http://127.0.0.1:4319/api/b/x; }
start_web() {
  (cd "$WEBSITE" && LINKS_LOCAL_DIR="$LINKS" exec timeout 5400 pnpm start -p 4319 >>"$TMP/web.txt" 2>&1) &
  WEB_PID=$!
  for _ in $(seq 1 60); do web_up && return 0; sleep 0.5; done
  echo "the website did not start"; tail -20 "$TMP/web.txt"; return 1
}
stop_web() {
  [[ -n "$WEB_PID" ]] && kill "$WEB_PID" 2>/dev/null
  lsof -ti tcp:4319 -sTCP:LISTEN | xargs kill 2>/dev/null
  for _ in $(seq 1 20); do web_up || break; sleep 0.5; done
  WEB_PID=""
}
lsof -ti tcp:4319 -sTCP:LISTEN | xargs kill 2>/dev/null
lsof -ti tcp:4320 -sTCP:LISTEN | xargs kill 2>/dev/null
start_web || exit 1
timeout 5400 python3 tool/link_proxy.py 4320 4319 "$REQ" &
PROXY_PID=$!

# ---- the alert tapper ----
timeout 600 xcodebuild build-for-testing -project tool/alerts/Tapper.xcodeproj -scheme TapperUITests \
  -destination "id=$UDID" -derivedDataPath "$DD" >"$TMP/tapper_build.txt" 2>&1 || { echo "tapper build failed"; tail -20 "$TMP/tapper_build.txt"; stop_web; exit 1; }
XCTESTRUN="$(ls "$DD"/Build/Products/*.xctestrun | head -1)"
rm -rf "$TAP_DIR"; mkdir -p "$TAP_DIR"
TEST_RUNNER_TAPPER_DIR="$TAP_DIR" TEST_RUNNER_RUN_SECONDS=5400 timeout 5600 \
  xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "id=$UDID" >"$TMP/tapper.txt" 2>&1 &
TAPPER_PID=$!
for _ in $(seq 1 120); do [[ -f "$TAP_DIR/ready" ]] && break; sleep 1; done
[[ -f "$TAP_DIR/ready" ]] || { echo "tapper did not start"; tail -20 "$TMP/tapper.txt"; stop_web; exit 1; }
tapper() {
  rm -f "$TAP_DIR/out"
  echo "$*" >"$TAP_DIR/cmd.tmp" && mv "$TAP_DIR/cmd.tmp" "$TAP_DIR/cmd"
  for _ in $(seq 1 "${TAP_WAIT:-240}"); do [[ -f "$TAP_DIR/out" ]] && break; sleep 0.25; done
  cat "$TAP_DIR/out" 2>/dev/null || echo "no answer"
}
restore() {
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLanguages 2>/dev/null || true
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" AppleLocale 2>/dev/null || true
  xcrun simctl ui "$UDID" content_size large 2>/dev/null || true
}
restore
tapper tap Cancel >/dev/null # an Open question left by an earlier run
LOG_PID=""
cleanup() {
  tapper quit >/dev/null; sleep 1; kill "$TAPPER_PID" 2>/dev/null
  [[ -n "$LOG_PID" ]] && kill "$LOG_PID" 2>/dev/null
  [[ -n "$PROXY_PID" ]] && kill "$PROXY_PID" 2>/dev/null
  stop_web
  restore
}
trap cleanup EXIT

face() { xcrun simctl spawn "$UDID" notifyutil -p "com.apple.BiometricKit_Sim.pearl.$1"; }
enrol() { xcrun simctl spawn "$UDID" notifyutil -s com.apple.BiometricKit.enrollmentChanged "$1"; xcrun simctl spawn "$UDID" notifyutil -p com.apple.BiometricKit.enrollmentChanged; }
enrol 1
urlfor() { python3 -c 'import sys, urllib.parse; print("file://" + urllib.parse.quote(sys.argv[1]))' "$1"; }

# ---- the app, with the test inside ----
timeout 600 flutter build ios --simulator --debug --target=integration_test/link_acceptance_test.dart \
  --dart-define=LINK_SERVICE=http://127.0.0.1:4320 --dart-define=SPEECH_AUDIO="$AUDIO" >"$TMP/build.txt" 2>&1 || { echo "build failed"; tail -20 "$TMP/build.txt"; exit 1; }
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
if [[ -n "$RESUME" ]]; then
  rm -rf "$DATA/Documents/link_test_status" "$DATA/tmp/fileacts"
  python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d["phase"]=int(sys.argv[2]); json.dump(d,open(f,"w"))' "$DATA/Documents/link_test_phase" "$RESUME"
  PHASES="$(echo "$PHASES" | tr ' ' '\n' | awk -v r="$RESUME" '$1>=r' | tr '\n' ' ')"
else
  rm -rf "$DATA/Documents/link_test_"* "$DATA/tmp/fileacts"
fi
mkdir -p "$DATA/tmp/fileacts"
[[ "$MODE" == ipad && -z "$RESUME" ]] && echo '{"phase":1,"prefix":"ipad-"}' >"$DATA/Documents/link_test_phase"
touch "$DATA/Documents/link_test_log.txt"
tail -n 0 -F "$DATA/Documents/link_test_log.txt" 2>/dev/null | sed -u 's/^/   test: /' &
LOG_PID=$!
ACTS="$DATA/tmp/fileacts"
tool/sim_permissions.sh grant "$UDID" >/dev/null

marked() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["urls"][sys.argv[2]])' "$DATA/Documents/link_test_phase" "$1"; }
# iOS asks "Open in “Upon Thy Head”?" before it hands an app a custom-scheme link (a universal link
# goes straight in); the tapper answers Open, as a person would
openlink() {
  xcrun simctl openurl "$UDID" "$1" || { echo "openurl failed"; return 1; }
  sleep 1.2
  local d; d="$(tapper alert)"
  if [[ "$d" == *"Open in"* ]]; then echo "asked, $(tapper tap Open | cut -c1-40)"; else echo "ok"; fi
}
testlink() { python3 -c 'import sys,urllib.parse as u; x=u.urlsplit(sys.argv[1]); print("uponthyhead-test://b/" + x.path.split("/b/")[1] + "#" + x.fragment)' "$1"; }

answer() {
  local n="$1"; shift
  local what="$*" ans="ok"
  case "$what" in
    "face match") face match ;;
    "apptap "*|"appdismiss "*) ans="$(tapper "$what")" ;;
    "shot "*) xcrun simctl io "$UDID" screenshot "$OUT_DIR/${what#shot }.png" >/dev/null 2>&1 || ans="screenshot failed" ;;
    "link "*) ans="$(openlink "${what#link }")" ;;
    "bg "*)
      set -- ${what#bg }
      ans="$(tapper home)"; sleep "$1"; ans="$ans; $(openlink "$2")" ;;
    "web "*)
      set -- ${what#web }
      ans="$(timeout 60 node tool/link_web.mjs "$1" "$OUT_DIR/$2.png" 2>&1 | tail -1)" ;;
    "plant "*)
      set -- ${what#plant }
      python3 -c 'import json,sys,time; json.dump({"c":sys.argv[2],"e":int(time.time()*1000)+86400000,"s":"planted"},open(sys.argv[3]+"/"+sys.argv[1]+".copy","w"))' "$1" "$2" "$LINKS" || ans="plant failed" ;;
    "server stop") stop_web; web_up && ans="still up" ;;
    "server start") start_web >/dev/null || ans="did not start" ;;
    "save "*)
      local f; f="$(echo "${what#save }" | base64 -d)"
      cp "$f" "$FIX/" || ans="copy failed"; ans="$ans $(stat -f %z "$f") bytes" ;;
    "file "*) xcrun simctl openurl "$UDID" "$(urlfor "$FIX/${what#file }")" || ans="openurl failed" ;;
    "pbclear") printf '' | xcrun simctl pbcopy "$UDID" ;;
    "pbinfo") ans="$(xcrun simctl pbinfo "$UDID" 2>&1 | tr '\n' ' ')" ;;
    "textsize "*) xcrun simctl ui "$UDID" content_size "${what#textsize }" || ans="failed" ;;
    *) ans="unknown" ;;
  esac
  echo "== ACT $n ${what%%#*} -> ${ans:0:160}" >&2
  echo "$ans" >"$ACTS/act_$n.tmp" && mv "$ACTS/act_$n.tmp" "$ACTS/act_$n"
}

serve() {
  local end=$((SECONDS + LIMIT)) st=""
  rm -f "$DATA/Documents/link_test_status"
  while ((SECONDS < end)); do
    for ask in "$ACTS"/ask_*; do
      [[ -f "$ask" ]] || continue
      local n="${ask##*_}"
      [[ "$n" == *.tmp ]] && continue
      local what; what="$(cat "$ask")"; rm -f "$ask"
      answer "$n" "$what"
    done
    if [[ -f "$DATA/Documents/link_test_status" ]]; then st="$(cat "$DATA/Documents/link_test_status")"; break; fi
    sleep 0.2
  done
  echo "${st:-timed out}"
}

status=1
for phase in $PHASES; do
  echo "== phase $phase"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 2
  # a new website process each phase: its count of links made per address starts again
  [[ "$phase" != 1 ]] && { stop_web; start_web || break; }
  restore
  case "$phase" in
    1|3) xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null ;;
    2|6) echo "== launched by the link: $(openlink "$(testlink "$(marked surgery)")")" ;;
    4) xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLanguages -array es
       xcrun simctl spawn "$UDID" defaults write "$BUNDLE" AppleLocale es_US
       xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null ;;
    5) xcrun simctl ui "$UDID" content_size accessibility-medium
       xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null ;;
  esac
  got="$(serve)"
  echo "== phase $phase: $got"
  case "$got" in
    "next "*) ;;
    done) status=0; echo "== ALL PHASES PASSED"; break ;;
    *) echo "== phase $phase FAILED"; break ;;
  esac
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
restore

# ---- what left the phone ----
echo "== the website's links folder: $LINKS"
echo "== requests the app made"
python3 - "$REQ" "$DATA/Documents/link_test_secrets.jsonl" <<'EOF' || status=1
import base64, json, sys
reqs = [json.loads(l) for l in open(sys.argv[1])]
secrets = [json.loads(l) for l in open(sys.argv[2])]
bad = []
for s in secrets:
    key = base64.urlsafe_b64decode(s["key"] + "=")
    forms = [s["key"], base64.b64encode(key).decode().rstrip("="), key.hex()]
    for r in reqs:
        body = base64.b64decode(r["body"])
        hay = r["path"] + "\n" + json.dumps(r["headers"])
        for f in forms:
            if f in hay or f.encode() in body:
                bad.append(f"key of {s['id']} in {r['method']} {r['path']}")
        if key in body:
            bad.append(f"raw key of {s['id']} in the body of {r['method']} {r['path']}")
        stop = s["stop"]
        own = r["method"] == "DELETE" and r["path"] == f"/api/b/{s['id']}"
        others = {k: v for k, v in r["headers"].items() if not (own and k.lower() == "authorization")}
        if stop in r["path"] or stop.encode() in body or stop in json.dumps(others):
            bad.append(f"stop token of {s['id']} in {r['method']} {r['path']} outside its own header")
        if own and r["headers"].get("Authorization", r["headers"].get("authorization")) not in (None, f"Bearer {stop}"):
            bad.append(f"odd Authorization on the stop of {s['id']}")
    if any("#" in r["path"] for r in reqs):
        bad.append("a fragment in a request path")
kinds = {}
for r in reqs:
    k = f"{r['method']} {'/api/b' if r['path'] == '/api/b' else '/api/b/<id>' if r['path'].startswith('/api/b/') else r['path']} → {r['status']}"
    kinds[k] = kinds.get(k, 0) + 1
print(f"   {len(reqs)} requests, {len(secrets)} links: " + ", ".join(f"{v}× {k}" for k, v in sorted(kinds.items())))
print("   headers seen: " + ", ".join(sorted({h for r in reqs for h in r['headers']})))
if bad:
    print("   FOUND: " + "; ".join(bad)); sys.exit(1)
print("   no key in any address, header or body; each stop token only in its own stop request's Authorization header")
EOF
grep '^RESULTS' "$DATA/Documents/link_test_log.txt" | tail -1
exit $status
