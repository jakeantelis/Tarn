#!/bin/zsh
# Builds the Mac App Store edition of Tarn: universal, sandboxed, no Sparkle, no tarnctl.
#
#   Tools/build-appstore.sh            local test build, ad hoc signed, sandbox on  -> build/Tarn-AppStore.app
#   TARN_MAS_APP_ID="3rd Party Mac Developer Application: ..." \
#   TARN_MAS_INSTALLER_ID="3rd Party Mac Developer Installer: ..." \
#   TARN_MAS_PROFILE=/path/Tarn_Mac_AppStore.provisionprofile \
#   Tools/build-appstore.sh            signed for the Store                        -> dist/Tarn-AppStore.pkg
#
# Upload the .pkg with Transporter. Needs the two Mac App Store certificates and a Mac App Store
# provisioning profile for com.antelislabs.tarn.ios, all made in the Apple developer account.
set -euo pipefail
setopt nullglob
cd "$(dirname "$0")/.."

TEAM=6G8C59T679
# The Store edition shares the iPhone app's App Store Connect record (one listing, macOS platform added),
# so it uses that record's bundle ID. The direct-download build keeps com.antelislabs.tarn.
BUNDLE=com.antelislabs.tarn.ios
APP=build/Tarn-AppStore.app
TMP=build/appstore
rm -rf "$APP" "$TMP"
mkdir -p "$TMP/arm64" "$TMP/x86_64" "$APP/Contents/MacOS" "$APP/Contents/Resources"

FLAGS=(-O -parse-as-library -swift-version 5 -D APPSTORE
    -framework SwiftUI -framework AppKit -framework AVFoundation -framework UserNotifications)
echo "Compiling (arm64 and x86_64)..."
swiftc "${FLAGS[@]}" -target arm64-apple-macos14.0  Sources/*.swift -o "$TMP/arm64/Tarn"
swiftc "${FLAGS[@]}" -target x86_64-apple-macos14.0 Sources/*.swift -o "$TMP/x86_64/Tarn"
lipo -create "$TMP/arm64/Tarn" "$TMP/x86_64/Tarn" -output "$APP/Contents/MacOS/Tarn"

mkdir -p "$APP/Contents/Resources/Sounds" "$APP/Contents/Resources/Icons" "$APP/Contents/Resources/Voice"
cp Resources/Sounds/*.{wav,caf,m4a} "$APP/Contents/Resources/Sounds/" 2>/dev/null || true
cp Resources/Icons/*.png "$APP/Contents/Resources/Icons/" 2>/dev/null || true
cp Resources/Voice/*.m4a "$APP/Contents/Resources/Voice/" 2>/dev/null || true
# The spoken breath cue (Voice): short clips per voice, plus an intro for each rhythm.
mkdir -p "$APP/Contents/Resources/Voice/Breath"
cp Resources/Voice/Breath/*.m4a "$APP/Contents/Resources/Voice/Breath/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE" "$APP/Contents/Info.plist"
# No network and no custom cryptography, so the export compliance question is answered in the plist.
/usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "$APP/Contents/Info.plist"
[[ -n "${TARN_MAS_BUILD:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $TARN_MAS_BUILD" "$APP/Contents/Info.plist"
# The Store listing is macOS version 1.0 (override with TARN_MAS_VERSION).
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${TARN_MAS_VERSION:-1.0}" "$APP/Contents/Info.plist"

# The Store updates the app, so the Sparkle keys come out of the copy of Info.plist.
PB=/usr/libexec/PlistBuddy
for key in SUFeedURL SUPublicEDKey SUEnableSystemProfiling SUScheduledCheckInterval; do
    $PB -c "Delete :$key" "$APP/Contents/Info.plist" 2>/dev/null || true
done

if [[ -n "${TARN_MAS_APP_ID:-}" ]]; then
    : "${TARN_MAS_INSTALLER_ID:?set TARN_MAS_INSTALLER_ID}" "${TARN_MAS_PROFILE:?set TARN_MAS_PROFILE}"
    cp "$TARN_MAS_PROFILE" "$APP/Contents/embedded.provisionprofile"
    ENT="$TMP/Tarn.entitlements"
    cp Resources/Tarn-AppStore.entitlements "$ENT"
    $PB -c "Add :com.apple.application-identifier string $TEAM.$BUNDLE" "$ENT"
    $PB -c "Add :com.apple.developer.team-identifier string $TEAM" "$ENT"
    # A profile downloaded in a browser carries com.apple.quarantine, which the Store rejects (ITMS-91109).
    xattr -cr "$APP"
    codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$TARN_MAS_APP_ID" "$APP"
    mkdir -p dist
    productbuild --component "$APP" /Applications --sign "$TARN_MAS_INSTALLER_ID" dist/Tarn-AppStore.pkg
    echo "Built dist/Tarn-AppStore.pkg. Upload it with Transporter."
else
    codesign --force --entitlements Resources/Tarn-AppStore.entitlements --sign - "$APP"
    echo "Built $APP (local test build: sandboxed, ad hoc signed, not for upload)."
fi
codesign -d --entitlements - "$APP" 2>&1 | grep -A1 sandbox || true
