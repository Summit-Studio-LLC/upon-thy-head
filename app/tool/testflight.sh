#!/bin/bash
# The iPhone and iPad release file for TestFlight: build it, sign it for the App Store, have Apple
# check it, and with --upload send it.
#
#   tool/testflight.sh            build, sign and check
#   tool/testflight.sh --upload   the same, then send it to App Store Connect
#
# Needs both App Store Connect keys in ~/.appstoreconnect/private_keys/ (the ids below are not
# secret; the .p8 files are). The Admin key signs, because the App Manager key cannot; the App
# Manager key checks and uploads. Checking and uploading both need an app entry for
# dev.summitstudio.uponThyHead in App Store Connect, which can only be made on the website.
#
# The build number is the part after + in pubspec.yaml's version. Apple refuses a number it has
# already seen for the same version, so raise it before each upload.
set -euo pipefail
cd "$(dirname "$0")/.."

UPLOAD_KEY=CWVL8DK36T
SIGN_KEY=RS6D26C7WT
ISSUER=36e57f22-076a-40a6-8b26-246e7bbcc0e0
KEYS="$HOME/.appstoreconnect/private_keys"
for k in $UPLOAD_KEY $SIGN_KEY; do
  [ -f "$KEYS/AuthKey_$k.p8" ] || { echo "no key at $KEYS/AuthKey_$k.p8"; exit 1; }
done

upload=0
[ "${1:-}" = "--upload" ] && upload=1

# The Summit Studio distribution key is found first in a signing keychain of its own (made for
# HiveCycle), whose password is not the Mac's login password: it sits in a file beside it. Locked,
# it puts a dialog on the Mac's screen that the login password cannot answer.
SIGNING="$HOME/.appstoreconnect/hivecycle-signing"
if [ -f "$SIGNING/keychain-password" ]; then
  # Lock it first. The keychain locks itself when the Mac sleeps, and after that (or after a password
  # dialog for it has been on screen) the Mac can refuse the right password with "The user name or
  # passphrase you entered is not correct". Locking it outright clears that; then the unlock works.
  security lock-keychain "$SIGNING/distribution.keychain-db" 2>/dev/null || true
  security unlock-keychain -p "$(cat "$SIGNING/keychain-password")" "$SIGNING/distribution.keychain-db"
fi
# Signing waits for ever, with nothing printed, while such a dialog goes unanswered. Sign a scrap
# file first, so that shows in ten seconds.
SCRAP=$(mktemp -d)
cp /bin/echo "$SCRAP/scrap"
if ! perl -e 'alarm shift; exec @ARGV' 10 codesign -f -s "Apple Distribution: Summit Studio LLC (7R77MUH4FF)" "$SCRAP/scrap" 2>/dev/null; then
  rm -rf "$SCRAP"
  echo "the distribution certificate cannot sign: a keychain dialog is waiting on the Mac's screen."
  echo "It wants the password of the keychain that holds the key, which may not be the login password."
  exit 1
fi
rm -rf "$SCRAP"

ARCHIVE=build/ios/archive/Runner.xcarchive
rm -rf build/ios/ipa build/ios/archive
mkdir -p build/ios/ipa
# Flutter prepares the Xcode project (version, build number, plugins) and Xcode archives and exports.
# Xcode is given the Admin key, so it fetches or makes the profiles itself: the Mac's own Xcode
# sign-in is not used, and a capability added to the entitlements is switched on for the App ID
# without a visit to the developer portal (App Attest was the first; `flutter build ipa` stopped on
# "Provisioning profile doesn't include the App Attest capability").
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEYS/AuthKey_$SIGN_KEY.p8"
  -authenticationKeyID $SIGN_KEY -authenticationKeyIssuerID $ISSUER)
flutter build ios --release --config-only
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" archive "${AUTH[@]}" \
  > build/ios/archive.log 2>&1 || { grep -E 'error:|FAILED' build/ios/archive.log | sort -u | head -20; echo "the archive was not built (build/ios/archive.log)"; exit 1; }

cat > build/ios/ipa/ExportOptions.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>7R77MUH4FF</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath build/ios/ipa \
  -exportOptionsPlist build/ios/ipa/ExportOptions.plist "${AUTH[@]}" \
  > build/ios/export.log 2>&1 || { grep -E 'error:|FAILED' build/ios/export.log | sort -u | head -20; echo "the export failed (build/ios/export.log)"; exit 1; }
IPA=$(ls build/ios/ipa/*.ipa | head -1)

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
unzip -qo "$IPA" 'Payload/*.app/Info.plist' 'Payload/*.app/embedded.mobileprovision' -d "$TMP"
APP=$(find "$TMP/Payload" -maxdepth 1 -name '*.app' | head -1)
echo "built $IPA: version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")" \
  "build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist"), $(du -h "$IPA" | cut -f1)"
# A file signed for development would be refused: say so here, not after the upload.
security cms -D -i "$APP/embedded.mobileprovision" > "$TMP/profile.plist"
if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$TMP/profile.plist" >/dev/null 2>&1; then
  echo "this file is signed for named phones, not for the App Store"; exit 1
fi

check() { # validate-app or upload-app
  local log="$TMP/$1.log"
  xcrun altool "--$1" -f "$IPA" -t ios --apiKey $UPLOAD_KEY --apiIssuer $ISSUER 2>&1 | tee "$log"
  ! grep -Eq '(^|[[:space:]])(ERROR:|Failed to (validate|upload))' "$log"
}
check validate-app || { echo "Apple's check failed: not uploading"; exit 1; }
[ $upload -eq 1 ] || { echo "checked. Run with --upload to send it."; exit 0; }
check upload-app || { echo "the upload failed"; exit 1; }
echo "uploaded. App Store Connect takes a few minutes to process it before it shows in TestFlight."
