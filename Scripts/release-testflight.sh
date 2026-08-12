#!/bin/bash
# Archives, signs and uploads the app to TestFlight.
#
#   Scripts/release-testflight.sh
#
# No Apple login, no Xcode Organizer, nothing to paste. It authenticates with
# the App Store Connect API key already on this machine plus the issuer ID in
# the login keychain, so the only thing it needs from you is the build number
# being right (see below).
#
# **Credentials, and why neither of them is in this repo.** The private key
# lives at ~/.appstoreconnect/private_keys/AuthKey_<id>.p8, which is the path
# `altool` searches on its own. The issuer ID is a UUID in the login keychain
# under the service name below. Store it once with:
#
#   security add-generic-password -U -s asc-api-issuer -a <KEY_ID> -w <ISSUER_UUID>
#
# Find both at App Store Connect > Users and Access > Integrations > App Store
# Connect API: the issuer ID is at the top of the page, the key ID is the row.
#
# **The build number is yours to set and this script will not touch it.**
# `xcodebuild -exportArchive` increments it silently when the number in the
# project is already on App Store Connect, because `manageAppVersionAndBuildNumber`
# defaults to true — on 2026-08-11 that shipped build 9 while the archive's own
# Info.plist still read 8, and the repo went on saying 8. The export options
# below set it false, so a number that is already taken fails the upload with a
# message instead of quietly becoming a different build. Bump
# CURRENT_PROJECT_VERSION in the project, commit it, then run this.
set -euo pipefail

KEY_ID="${ASC_KEY_ID:-39J453KSX8}"
KEYCHAIN_SERVICE="asc-api-issuer"
SCHEME="AIKeyboard"
PROJECT="AIKeyboard.xcodeproj"

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

issuer="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEY_ID" -w 2>/dev/null || true)"
if [ -z "$issuer" ]; then
    echo "No issuer ID in the keychain for key $KEY_ID." >&2
    echo "  security add-generic-password -U -s $KEYCHAIN_SERVICE -a $KEY_ID -w <ISSUER_UUID>" >&2
    exit 1
fi
key_path="$HOME/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8"
if [ ! -f "$key_path" ]; then
    echo "No API key at $key_path — download it from App Store Connect." >&2
    exit 1
fi

build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

cat > "$build/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>9R8P28G4BJ</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>destination</key><string>export</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "==> Archiving"
xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -archivePath "$build/$SCHEME.xcarchive" \
    -allowProvisioningUpdates > "$build/archive.log" 2>&1 || {
    tail -30 "$build/archive.log" >&2
    echo "archive failed — full log at $build/archive.log" >&2
    exit 1
}

echo "==> Exporting"
xcodebuild -exportArchive \
    -archivePath "$build/$SCHEME.xcarchive" \
    -exportOptionsPlist "$build/ExportOptions.plist" \
    -exportPath "$build/export" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$key_path" \
    -authenticationKeyID "$KEY_ID" \
    -authenticationKeyIssuerID "$issuer" > "$build/export.log" 2>&1 || {
    tail -30 "$build/export.log" >&2
    echo "export failed — full log at $build/export.log" >&2
    exit 1
}

ipa="$build/export/$SCHEME.ipa"
# Read from the *ipa*, never from the archive. They disagreed once and the
# archive was the one that was wrong; this is the number that actually ships.
shipped="$(unzip -p "$ipa" "Payload/$SCHEME.app/Info.plist" | plutil -extract CFBundleVersion raw -)"
version="$(unzip -p "$ipa" "Payload/$SCHEME.app/Info.plist" | plutil -extract CFBundleShortVersionString raw -)"
echo "==> Uploading version $version build $shipped"

xcrun altool --upload-app -f "$ipa" -t ios \
    --apiKey "$KEY_ID" --apiIssuer "$issuer" 2>&1 | tee "$build/upload.log"

# **`set -e` cannot see this one, and the script claimed success over a failed
# upload because of it.** A pipeline's status is its *last* command's, which here
# is `tee` and is always 0 — so on 2026-08-12 altool refused build 13 with a 409
# ("the bundle version must be higher than the previously uploaded version"), the
# script printed "Uploaded version 0.1 build 13", exited 0, and the only thing
# that said otherwise was the error text scrolled off above it. A release script
# that reports success on a failure is worse than no script: the number in the
# repo goes on saying it shipped.
status="${PIPESTATUS[0]}"
if [ "$status" -ne 0 ]; then
    echo >&2
    echo "upload failed — full log at $build/upload.log" >&2
    # The commonest failure by far, and the one with an obvious next step.
    if grep -q "previously uploaded version" "$build/upload.log"; then
        echo "Build $shipped is already on App Store Connect." >&2
        echo "Bump CURRENT_PROJECT_VERSION in $PROJECT, commit it, then run this again." >&2
    fi
    exit "$status"
fi

echo
echo "Uploaded version $version build $shipped. Processing takes a few minutes."
echo "https://appstoreconnect.apple.com/apps"
