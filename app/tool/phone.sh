#!/bin/bash
# Put Upon Thy Head on an iPhone plugged into this Mac: build, install, open.
#
#   tool/phone.sh [options]
#
#   (nothing)      build in profile mode (real speed), install, open
#   --release      build in release mode instead (exactly what people would get)
#   --seed         start with the five sample blessings (only if the phone has none yet)
#   --dense        start with the 120 test blessings (only if the phone has none yet)
#   --check        include the phone check page, and open it at launch
#   --spanish      open the app in Spanish
#   --log          stay attached and print the app's log; with --check, the report is saved on the Mac
#   --report       fetch the last phone check report from the phone (no build)
#   --phone NAME   which iPhone, when more than one is plugged in (its name or identifier)
#   --build-only   build, but do not look for a phone
#   --help         this text
#
# Uses only Xcode's own tools (xcrun devicectl) and Flutter. Logs: build/phone/.
set -uo pipefail
cd "$(dirname "$0")/.."
BUNDLE=dev.summitstudio.uponThyHead
OUT=build/phone
mkdir -p "$OUT"

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

mode=profile seed= check=0 spanish=0 log=0 report=0 phone= buildonly=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) mode=release ;;
    --profile) mode=profile ;;
    --seed) seed=true ;;
    --dense) seed=dense ;;
    --check) check=1 ;;
    --spanish) spanish=1 ;;
    --log) log=1 ;;
    --report) report=1 ;;
    --build-only) buildonly=1 ;;
    --phone)
      [[ $# -ge 2 ]] || { say "--phone needs the iPhone's name or identifier after it."; exit 2; }
      phone="$2"
      shift
      ;;
    --phone=*) phone="${1#--phone=}" ;;
    -h | --help) usage; exit 0 ;;
    -*) say "\"$1\" is not an option this script knows."; say; usage; exit 2 ;;
    *) phone="$1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- explaining failures

# One plain line for each first-run failure we know, from whatever a tool printed.
explain() {
  local text="$1" found=0
  if grep -qiE "locked|kAMDMobileImageMounterDeviceLocked|passcode protected" <<<"$text"; then
    say "→ The iPhone is locked. Unlock it, keep it on the Home Screen, and run this again."; found=1
  fi
  if grep -qiE "developer mode" <<<"$text"; then
    say "→ Developer Mode is off. On the iPhone: Settings > Privacy & Security > Developer Mode (near the bottom) > On, restart when asked, then tap Turn On."; found=1
  fi
  if grep -qiE "explicitly trusted|invalid code signature|untrusted developer|0xe8008012" <<<"$text"; then
    say "→ The iPhone does not trust this developer yet. On the iPhone: Settings > General > VPN & Device Management > Apple Development > Trust. Then run this again."; found=1
  fi
  if grep -qiE "provisioning profile|not included in|0xe8008015|ApplicationVerificationFailed|No profiles for|requires a provisioning|not been registered|No Account for Team" <<<"$text"; then
    say "→ Signing: this iPhone is not in the app's development profile yet. Fix once: open app/ios/Runner.xcworkspace in Xcode, choose this iPhone at the top of the window, press Run (▶), wait for the app to open, then run this script again."; found=1
  fi
  if grep -qiE "not paired|pairing|trust this computer|PairingDialogResponsePending|unpaired" <<<"$text"; then
    say "→ The iPhone has not trusted this Mac. Unlock it; when it asks \"Trust This Computer?\" tap Trust and enter the passcode. Then run this again."; found=1
  fi
  if grep -qiE "disk image|DDI|not supported by this version of Xcode|newer than|unsupported os" <<<"$text"; then
    say "→ This Mac's Xcode is too old for the iPhone's iOS. Update Xcode from the App Store, or use another iPhone."; found=1
  fi
  if grep -qiE "Unable to locate a device|unable to locate|not found|disconnected|lost connection" <<<"$text" && [[ $found -eq 0 ]]; then
    say "→ The iPhone went away. Check the cable, unlock the phone, and run this again."; found=1
  fi
  return $((1 - found))
}

# ---------------------------------------------------------------- the phone

# The iPhones this Mac knows, one per line: identifier|udid|name|model|iOS|connected|paired|devmode
# (tests may point PHONE_SH_DEVICES_JSON at a saved `devicectl list devices --json-output` file)
devices() {
  local json="${PHONE_SH_DEVICES_JSON:-}"
  if [[ -z "$json" ]]; then
    json="$OUT/devices.json"
    rm -f "$json"
    xcrun devicectl list devices --json-output "$json" >"$OUT/devices.txt" 2>&1 || true
    [[ -s "$json" ]] || { say "Could not ask Xcode about iPhones:"; cat "$OUT/devices.txt"; exit 1; }
  fi
  python3 - "$json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for x in d.get("result", {}).get("devices", []):
    hw, dp, cp = x.get("hardwareProperties", {}), x.get("deviceProperties", {}), x.get("connectionProperties", {})
    if hw.get("platform") != "iOS" or hw.get("reality", "physical") != "physical":
        continue
    # Xcode leaves out the marketing name for phones it has not set up yet
    names = {"iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
             "iPhone17,5": "iPhone 16e", "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max", "iPhone13,2": "iPhone 12"}
    pt = hw.get("productType", "")
    model = hw.get("marketingName") or (f"{names[pt]}, {pt}" if pt in names else pt) or "iPhone"
    connected = "yes" if cp.get("tunnelState") not in (None, "unavailable") or cp.get("transportType") else "no"
    print("|".join([x.get("identifier", ""), hw.get("udid", ""), dp.get("name", "iPhone").replace("|", "/"), model,
                    dp.get("osVersionNumber", "?"), connected, cp.get("pairingState", "?"), str(dp.get("developerModeStatus"))]))
PY
}

pick_phone() {
  local all connected n
  all="$(devices)"
  connected="$(awk -F'|' '$6 == "yes"' <<<"$all")"
  n=$(grep -c . <<<"$connected")
  if [[ $n -eq 0 ]]; then
    say "No iPhone is connected to this Mac."
    say
    say "  1. Plug the iPhone into this Mac with a cable."
    say "  2. Unlock it (Face ID or passcode) and stay on the Home Screen."
    say "  3. If it asks \"Trust This Computer?\", tap Trust and enter the passcode."
    say "  4. Developer Mode must be on: Settings > Privacy & Security > Developer Mode > On."
    say "     The phone restarts; after it does, unlock it and tap Turn On."
    say "     (If Developer Mode is not in that list, keep the phone plugged in, open Xcode,"
    say "     choose Window > Devices and Simulators, wait a minute, and look again.)"
    say "  5. Run this again."
    if [[ -n "$all" ]]; then
      say
      say "This Mac has seen these iPhones before (none is connected now):"
      awk -F'|' '{ printf "  - %s (%s, iOS %s)\n", $3, $4, $5 }' <<<"$all"
    fi
    exit 1
  fi
  local chosen="$connected"
  if [[ -n "$phone" ]]; then
    local want
    want="$(norm "$phone")"
    chosen="$(while IFS= read -r l; do
      IFS='|' read -r id udid name _ <<<"$l"
      if [[ "$want" == "$(norm "$id")" || "$want" == "$(norm "$udid")" || "$want" == "$(norm "$name")" ]]; then echo "$l"; fi
    done <<<"$connected")"
    n=$(grep -c . <<<"$chosen")
    if [[ $n -eq 0 ]]; then
      say "No connected iPhone is called \"$phone\". Connected now:"
      list_phones "$connected"
      exit 1
    fi
  fi
  if [[ $n -gt 1 ]]; then
    say "More than one iPhone is connected. Say which, by name or identifier:"
    list_phones "$chosen"
    say
    say "For example:  tool/phone.sh --phone $(head -1 <<<"$chosen" | cut -d'|' -f1) $(args_again)"
    exit 1
  fi
  IFS='|' read -r PHONE_ID PHONE_UDID PHONE_NAME PHONE_MODEL PHONE_OS _ PHONE_PAIRED PHONE_DEVMODE <<<"$chosen"
}

# Lower case, with the curly apostrophe iOS puts in "Noah’s iPhone" made straight, for comparing.
norm() { sed "s/’/'/g" <<<"$1" | tr '[:upper:]' '[:lower:]'; }

list_phones() { awk -F'|' '{ printf "  %s  %s (%s, iOS %s)\n", $1, $3, $4, $5 }' <<<"$1"; }

args_again() {
  local a=()
  [[ $mode == release ]] && a+=(--release)
  [[ $seed == true ]] && a+=(--seed)
  [[ $seed == dense ]] && a+=(--dense)
  [[ $check == 1 ]] && a+=(--check)
  [[ $spanish == 1 ]] && a+=(--spanish)
  [[ $log == 1 ]] && a+=(--log)
  echo "${a[*]:-}"
}

# Before building: what can already be seen to be wrong with the phone.
preflight() {
  say "iPhone: $PHONE_NAME ($PHONE_MODEL, iOS $PHONE_OS)"
  if [[ "$PHONE_PAIRED" != "paired" ]]; then
    say "→ The iPhone has not trusted this Mac yet. Unlock it; when it asks \"Trust This Computer?\", tap Trust and enter the passcode. Then run this again."
    exit 1
  fi
  if [[ "$PHONE_DEVMODE" == "disabled" ]]; then
    say "→ Developer Mode is off. On the iPhone: Settings > Privacy & Security > Developer Mode (near the bottom) > On. The phone restarts; unlock it, tap Turn On, then run this again."
    exit 1
  fi
  local sdk phone_major
  sdk="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo 0)"
  phone_major="${PHONE_OS%%.*}"
  if [[ "$phone_major" =~ ^[0-9]+$ && "$phone_major" -gt "${sdk%%.*}" ]]; then
    say "Note: the iPhone runs iOS $PHONE_OS and this Mac's Xcode was made for iOS $sdk. If installing fails, update Xcode from the App Store."
  fi
}

# ---------------------------------------------------------------- the report only

if [[ $report -eq 1 ]]; then
  pick_phone
  preflight
  dest="$OUT/phone-check-$(date +%Y%m%d-%H%M%S).txt"
  if xcrun devicectl device copy from --device "$PHONE_ID" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
      --source Documents/phone-check.txt --destination "$dest" >"$OUT/copy.log" 2>&1; then
    say "Report saved: $PWD/$dest"
    exit 0
  fi
  say "Could not fetch the report:"; tail -5 "$OUT/copy.log"
  explain "$(cat "$OUT/copy.log")" || say "→ Has the phone check page finished on the phone? It saves the report when every check is done."
  exit 1
fi

# ---------------------------------------------------------------- build

if [[ $buildonly -eq 0 ]]; then
  pick_phone
  preflight
fi

defines=()
[[ -n "$seed" ]] && defines+=(--dart-define=SEED_SAMPLES=$seed)
[[ $check -eq 1 ]] && defines+=(--dart-define=PHONE_CHECK=true)

build() {
  flutter build ios --"$mode" ${defines[@]+"${defines[@]}"} >"$OUT/build.log" 2>&1
}

what="$mode"
[[ $seed == true ]] && what+=", the five samples"
[[ $seed == dense ]] && what+=", the 120 test blessings"
[[ $check -eq 1 ]] && what+=", with the phone check"
step "Building ($what). This takes a minute or two."
if ! build; then
  say "The build failed. The end of its log ($OUT/build.log):"
  grep -E "error:|Error|❌|failed" "$OUT/build.log" | tail -15
  explain "$(cat "$OUT/build.log")" || true
  exit 1
fi
APP=build/ios/iphoneos/Runner.app
grep -E "✓ Built" "$OUT/build.log" || say "Built $APP"

if [[ $buildonly -eq 1 ]]; then
  say "Built only; no phone was looked for."
  exit 0
fi

# The team's development profile must name this phone. Xcode adds a phone it can see when it builds
# for that phone, so if it is missing, build once for it and then build again.
profile_has_phone() { security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | grep -q "$PHONE_UDID"; }
if [[ -n "$PHONE_UDID" ]] && ! profile_has_phone; then
  step "This iPhone is new to the app's signing profile; asking Xcode to add it."
  config=Profile
  [[ $mode == release ]] && config=Release
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration "$config" -destination "id=$PHONE_UDID" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration SYMROOT="$PWD/build/ios" build >"$OUT/register.log" 2>&1 || true
  build || { say "The build failed after adding the phone ($OUT/build.log)."; exit 1; }
  if ! profile_has_phone; then
    say "Xcode did not add this iPhone to the profile ($OUT/register.log)."
    explain "$(cat "$OUT/register.log")" ||
      say "→ Signing: open app/ios/Runner.xcworkspace in Xcode, choose this iPhone at the top, press Run (▶) once, then run this script again."
    exit 1
  fi
fi

# ---------------------------------------------------------------- install and open

step "Installing on $PHONE_NAME."
if ! xcrun devicectl device install app --device "$PHONE_ID" "$APP" >"$OUT/install.log" 2>&1; then
  say "Installing failed:"
  grep -E "ERROR|error" "$OUT/install.log" | head -5
  explain "$(cat "$OUT/install.log")" || say "→ Unlock the iPhone and run this again. The full message is in $OUT/install.log."
  exit 1
fi
say "Installed."

launch=(xcrun devicectl device process launch --device "$PHONE_ID" --terminate-existing)
[[ $log -eq 1 ]] && launch+=(--console)
launch+=("$BUNDLE")
[[ $check -eq 1 ]] && launch+=(--open-phone-check)
[[ $spanish -eq 1 ]] && launch+=(-AppleLanguages "(es)" -AppleLocale es_US)

step "Opening the app."
if [[ $log -eq 0 ]]; then
  if ! "${launch[@]}" >"$OUT/launch.log" 2>&1; then
    say "Opening failed:"
    grep -E "ERROR|error" "$OUT/launch.log" | head -5
    explain "$(cat "$OUT/launch.log")" || say "→ Unlock the iPhone and open Upon Thy Head from the Home Screen. The full message is in $OUT/launch.log."
    exit 1
  fi
  say "Upon Thy Head is open on $PHONE_NAME."
  [[ $mode == profile ]] && say "If the phone asks to find devices on your local network, either answer is fine: that question is Flutter's test tooling, not the app's."
  [[ $check -eq 1 ]] && say "The phone check runs by itself. When it is done: tap Copy report, or run  tool/phone.sh --report  to fetch it."
  exit 0
fi

# --log: stay attached; keep the whole log, and cut out each phone check report as it arrives
stamp="$(date +%Y%m%d-%H%M%S)"
logfile="$OUT/log-$stamp.txt"
say "Attached. The app's log follows (also saved to $PWD/$logfile). Press Control-C to stop; the app keeps running."
"${launch[@]}" 2>&1 | tee "$logfile" | {
  inside=0 n=0 file=
  while IFS= read -r line; do
    printf '%s\n' "$line"
    if [[ "$line" == *"===== UPON THY HEAD PHONE CHECK BEGIN ====="* ]]; then
      inside=1 n=$((n + 1)) file="$OUT/phone-check-$stamp-$n.txt"
      : >"$file"
    elif [[ "$line" == *"===== UPON THY HEAD PHONE CHECK END ====="* && $inside -eq 1 ]]; then
      inside=0
      printf '\n== Phone check report saved: %s\n\n' "$PWD/$file"
    elif [[ $inside -eq 1 ]]; then
      printf '%s\n' "$line" >>"$file"
    fi
  done
}
explain "$(tail -20 "$logfile")" || true
