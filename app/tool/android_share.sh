#!/bin/bash
# Sending and receiving a blessing on Android (docs/android-plan.md tasks 13 and 14), unattended,
# against the website running on this Mac with a local store:
#
#   tool/android_share.sh [avd] [--only 1,9,5,3,4,6,8,10]     default Pixel_10_Pro and 1,9,5,3,4,6,8
#
# Starts the website (../website, `pnpm start` on 4319, links in a new temporary folder) and
# tool/link_proxy.py on 4320 in front of it, writing down every request the app makes; builds a debug
# APK with LINK_SERVICE=http://10.0.2.2:4320 (the Mac as the emulator sees it) and the five samples;
# boots the emulator with its audio off and its low-storage lines lowered; runs
# tool/android_share.py; then checks the requests for keys and stop tokens, uninstalls the app, puts
# the storage settings back, shuts the emulator down and stops the website and proxy. Links reach
# the app as Android hands it a verified App Link: `am start -a VIEW -d https://uponthyhead.app/b/…`.
# Results, screenshots and summary.json land in build/android_share/<avd>/. Every step has a limit.
set -uo pipefail
cd "$(dirname "$0")/.."
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"
AVD=Pixel_10_Pro
[[ $# -gt 0 && "$1" != --* ]] && { AVD=$1; shift; }
OUT="$PWD/build/android_share/$AVD"
APK=build/app/outputs/flutter-apk/app-debug.apk
WEBSITE="$(cd ../website && pwd)"
TMP="$(mktemp -d)"
LINKS="$TMP/links"
REQ="$OUT/requests.jsonl"
rm -rf "$OUT"; mkdir -p "$OUT" "$LINKS"; : >"$REQ"

limit() { # limit SECONDS command...: stopped if it runs longer
  local s=$1; shift
  perl -e 'alarm shift; exec @ARGV or die "cannot run $ARGV[0]"' "$s" "$@"
  local code=$?
  [[ $code == 142 ]] && echo "TIMED OUT after ${s}s: $*"
  return $code
}

WEB_PID="" PROXY_PID="" CTL_PID="" started=0 DEV="" saved_max="" saved_pct=""
web_up() { curl -s -o /dev/null --max-time 2 http://127.0.0.1:4319/api/b/x; }
start_web() {
  (cd "$WEBSITE" && LINKS_LOCAL_DIR="$LINKS" exec perl -e 'alarm 5400; exec @ARGV' pnpm start -p 4319 >>"$OUT/web.txt" 2>&1) &
  WEB_PID=$!
  for _ in $(seq 1 60); do web_up && return 0; sleep 0.5; done
  echo "the website did not start"; tail -20 "$OUT/web.txt"; return 1
}
stop_web() {
  [[ -n "$WEB_PID" ]] && kill "$WEB_PID" 2>/dev/null
  lsof -ti tcp:4319 -sTCP:LISTEN | xargs kill 2>/dev/null
  for _ in $(seq 1 20); do web_up || break; sleep 0.5; done
  WEB_PID=""
}
cleanup() {
  local rc=$?
  [[ -n "$CTL_PID" ]] && kill "$CTL_PID" 2>/dev/null
  if [[ -n "$DEV" ]]; then
    adb -s "$DEV" uninstall dev.summitstudio.uponthyhead >/dev/null 2>&1
    adb -s "$DEV" shell rm -f '/sdcard/Download/*.blessing' /sdcard/Download/Notes.zzz >/dev/null 2>&1
    adb -s "$DEV" shell cmd locale set-device-locale en-US >/dev/null 2>&1
    adb -s "$DEV" shell settings put system font_scale 1.0 >/dev/null 2>&1
    adb -s "$DEV" shell wm density reset >/dev/null 2>&1
    for kv in "sys_storage_threshold_max_bytes:$saved_max" "sys_storage_threshold_percentage:$saved_pct"; do
      k=${kv%%:*}; v=${kv#*:}
      if [[ "$v" == null || -z "$v" ]]; then adb -s "$DEV" shell settings delete global "$k" >/dev/null 2>&1
      else adb -s "$DEV" shell settings put global "$k" "$v"; fi
    done
  fi
  if [[ $started == 1 ]]; then
    adb -s "$DEV" emu kill >/dev/null 2>&1
    for _ in $(seq 60); do adb devices | grep -q "^$DEV" || break; sleep 1; done
    echo "== emulator shut down"
  fi
  [[ -n "$PROXY_PID" ]] && kill "$PROXY_PID" 2>/dev/null
  lsof -ti tcp:4320 -sTCP:LISTEN | xargs kill 2>/dev/null
  stop_web
  echo "== website and proxy stopped"
  exit $rc
}
trap cleanup EXIT

if [[ -z "${NO_BUILD:-}" ]]; then
  limit 900 flutter build apk --debug --target-platform android-arm64 --dart-define=SEED_SAMPLES=true \
    --dart-define=LINK_SERVICE=http://10.0.2.2:4320 >"$OUT/build.txt" 2>&1 || { echo "the build failed"; tail -20 "$OUT/build.txt"; exit 1; }
fi

lsof -ti tcp:4319 -sTCP:LISTEN | xargs kill 2>/dev/null
lsof -ti tcp:4320 -sTCP:LISTEN | xargs kill 2>/dev/null
start_web || exit 1
perl -e 'alarm 5400; exec @ARGV' python3 tool/link_proxy.py 4320 4319 "$REQ" &
PROXY_PID=$!
# the driver asks for the website to stop or start (no internet) through $OUT/ctl
( while true; do
    if [[ -f "$OUT/ctl" ]]; then
      case "$(cat "$OUT/ctl")" in stop) stop_web ;; start) web_up || start_web >/dev/null ;; esac
      rm -f "$OUT/ctl"
    fi
    sleep 0.3
  done ) &
CTL_PID=$!

if [[ -n "$(adb devices | awk '/^emulator-/{print $1; exit}')" ]]; then
  echo "an emulator is already running; shut it down first, so this run starts it with -no-audio"
  exit 1
fi
echo "== booting $AVD"
emulator -avd "$AVD" -no-snapshot-load -no-boot-anim -no-audio -crash-report-mode never >"$OUT/emulator.log" 2>&1 &
started=1
for _ in $(seq 120); do
  DEV=$(adb devices | awk '/^emulator-/{print $1; exit}')
  [[ -n "$DEV" && "$(adb -s "$DEV" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && break
  sleep 2
done
[[ -n "$DEV" ]] || { echo "the emulator did not boot"; exit 1; }
echo "== on $DEV, Android $(adb -s "$DEV" shell getprop ro.build.version.release | tr -d '\r')"
adb -s "$DEV" shell settings put global sysui_demo_allowed 1
adb -s "$DEV" shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null
adb -s "$DEV" shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 >/dev/null
saved_max=$(adb -s "$DEV" shell settings get global sys_storage_threshold_max_bytes | tr -d '\r')
saved_pct=$(adb -s "$DEV" shell settings get global sys_storage_threshold_percentage | tr -d '\r')
adb -s "$DEV" shell settings put global sys_storage_threshold_max_bytes 209715200
adb -s "$DEV" shell settings put global sys_storage_threshold_percentage 1
adb -s "$DEV" uninstall dev.summitstudio.uponthyhead >/dev/null 2>&1
limit 240 adb -s "$DEV" install "$APK" >/dev/null || { echo "the install failed"; exit 1; }

limit 2400 python3 tool/android_share.py "$DEV" "$OUT" "$APK" "$LINKS" "$REQ" "$@"
code=$?

# ---- what left the phone: no key anywhere; each stop token only in its own stop's header ----
echo "== requests the app made"
python3 - "$REQ" "$OUT/made.json" <<'PY' || code=1
import base64, json, sys
reqs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
made = json.load(open(sys.argv[2])) if sys.argv[2] else {}
keys = [l.split('#')[1] for l in made.values() if l and '#' in l]
stops = {}
for r in reqs:
    if r['method'] == 'POST' and r.get('answer'):
        try:
            a = json.loads(r['answer']); stops[a['id']] = a['stop']
        except Exception:
            pass
bad = []
for r in reqs:
    body = base64.b64decode(r['body'])
    hay = r['path'] + '\n' + json.dumps(r['headers'])
    for k in keys:
        raw = base64.urlsafe_b64decode(k + '=')
        for f in [k, base64.b64encode(raw).decode().rstrip('='), raw.hex()]:
            if f in hay or f.encode() in body:
                bad.append(f"a key in {r['method']} {r['path']}")
        if raw in body:
            bad.append(f"a raw key in the body of {r['method']} {r['path']}")
    if '#' in r['path']:
        bad.append('a fragment in a request path')
    for ident, stop in stops.items():
        own = r['method'] == 'DELETE' and r['path'] == f'/api/b/{ident}'
        others = {k: v for k, v in r['headers'].items() if not (own and k.lower() == 'authorization')}
        if stop in r['path'] or stop.encode() in body or stop in json.dumps(others):
            bad.append(f"the stop token of {ident} in {r['method']} {r['path']} outside its own header")
        if own and r['headers'].get('Authorization', r['headers'].get('authorization')) != f'Bearer {stop}':
            bad.append(f'odd Authorization on the stop of {ident}')
kinds = {}
for r in reqs:
    k = f"{r['method']} {'/api/b' if r['path'] == '/api/b' else '/api/b/<id>'} → {r['status']}"
    kinds[k] = kinds.get(k, 0) + 1
print(f"   {len(reqs)} requests, {len(keys)} links made by the app, {len(stops)} stop tokens: " + ', '.join(f'{v}× {k}' for k, v in sorted(kinds.items())))
print('   headers seen: ' + ', '.join(sorted({h for r in reqs for h in r['headers']})))
if bad:
    print('   FOUND: ' + '; '.join(bad)); sys.exit(1)
print('   PASS  2: no key in any address, header or body; each stop token only in its own stop request\'s Authorization header')
PY
echo "== results in $OUT/summary.json"
exit $code
