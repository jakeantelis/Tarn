#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Stillwater.app
TMP=build/universal
DIST=dist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)

DEV_ID="D430FCAFBA0DBC0F48D765E55C07BF3BA1FCEF85"
NOTARY_PROFILE="jake-antelis"

rm -rf "$APP" "$TMP"
mkdir -p "$TMP/arm64" "$TMP/x86_64" "$APP/Contents/MacOS" "$APP/Contents/Resources"

FLAGS=(
    -O
    -parse-as-library
    -swift-version 5
    -framework SwiftUI
    -framework AppKit
    -framework AVFoundation
    -framework ServiceManagement
)

echo "Compiling arm64..."
swiftc Sources/*.swift -target arm64-apple-macos14.0 "${FLAGS[@]}" -o "$TMP/arm64/Stillwater"

echo "Compiling x86_64..."
swiftc Sources/*.swift -target x86_64-apple-macos14.0 "${FLAGS[@]}" -o "$TMP/x86_64/Stillwater"

lipo -create "$TMP/arm64/Stillwater" "$TMP/x86_64/Stillwater" -output "$APP/Contents/MacOS/Stillwater"

cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
mkdir -p "$APP/Contents/Resources/Sounds"
for f in Resources/Sounds/*.(wav|caf|m4a)(N); do cp "$f" "$APP/Contents/Resources/Sounds/"; done
cp Tools/stillwaterctl "$APP/Contents/Resources/stillwaterctl"
chmod +x "$APP/Contents/Resources/stillwaterctl"
date "+%Y-%m-%d %H:%M:%S" > "$APP/Contents/Resources/BUILD_STAMP"

# ---- Signing ----
SIGNED=false
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEV_ID"; then
    echo "Signing with $DEV_ID (hardened runtime + timestamp)..."
    if codesign --force --options runtime --timestamp --sign "$DEV_ID" "$APP" 2>&1; then
        if codesign -dv --verbose=2 "$APP" 2>&1 | grep "Authority=Developer ID Certification Authority" >/dev/null; then
            codesign --verify --deep --strict "$APP"
            SIGNED=true
        else
            echo "warning: signing identity is not Apple-issued; Developer ID Certification Authority is missing" >&2
        fi
    fi
fi
if [[ "$SIGNED" != true ]]; then
    echo "warning: no Developer ID identity found, falling back to ad-hoc signature" >&2
    if ! codesign --force --sign - "$APP" 2>&1; then
        echo "warning: ad-hoc codesign failed, continuing unsigned" >&2
    fi
fi

ARCHS=$(lipo -archs "$APP/Contents/MacOS/Stillwater")
echo "Universal binary: $ARCHS"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
    echo "ERROR: expected both arm64 and x86_64 in $ARCHS" >&2
    exit 1
fi

# ---- Notarization ----
NOTARIZED=false
if [[ "$SIGNED" == true ]] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    mkdir -p "$DIST"
    rm -f "$DIST/Stillwater-notary.zip"
    ditto -c -k --norsrc --noextattr --keepParent "$APP" "$DIST/Stillwater-notary.zip"
    echo "Submitting to Apple notary service..."
    xcrun notarytool submit "$DIST/Stillwater-notary.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$DIST/Stillwater-notary.zip"
    xcrun stapler staple "$APP"
    NOTARIZED=true
    echo "Notarized and stapled."
else
    echo "note: notarization skipped (needs Developer ID + keychain profile '$NOTARY_PROFILE')"
fi

mkdir -p "$DIST"
rm -f "$DIST/Stillwater.zip" "$DIST/Stillwater.zip.sha256"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$DIST/Stillwater.zip"
(cd "$DIST" && shasum -a 256 Stillwater.zip > Stillwater.zip.sha256)
echo "Packaged $DIST/Stillwater.zip ($VERSION) signed=$SIGNED notarized=$NOTARIZED"
cat "$DIST/Stillwater.zip.sha256"

# ---- DMG (friendly drag-to-Applications installer) ----
DMG="$DIST/Stillwater.dmg"
DMG_NOTARIZED=false
DMG_STAGE=build/dmg
rm -f "$DMG" "$DMG.sha256"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/Stillwater.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "Stillwater" -srcfolder "$DMG_STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$DMG_STAGE"

if [[ "$SIGNED" == true ]]; then
    codesign --force --timestamp --sign "$DEV_ID" "$DMG"
fi
if [[ "$NOTARIZED" == true ]]; then
    echo "Notarizing DMG..."
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    DMG_NOTARIZED=true
    echo "DMG notarized and stapled."
else
    echo "note: DMG notarization skipped (app not notarized)"
fi
(cd "$DIST" && shasum -a 256 Stillwater.dmg > Stillwater.dmg.sha256)
echo "Packaged $DMG ($VERSION) signed=$SIGNED notarized=$DMG_NOTARIZED"
cat "$DIST/Stillwater.dmg.sha256"

if [[ "${1:-}" == "--publish" ]]; then
    if [[ "$SIGNED" != true || "$NOTARIZED" != true || "$DMG_NOTARIZED" != true ]]; then
        echo "ERROR: refusing to publish without Apple Developer ID signing and notarization" >&2
        exit 1
    fi
    spctl -a -vv "$APP"
    gh release create "v$VERSION" \
        "$DIST/Stillwater.zip" \
        "$DIST/Stillwater.zip.sha256" \
        "$DIST/Stillwater.dmg" \
        "$DIST/Stillwater.dmg.sha256" \
        --title "Stillwater $VERSION" \
        --notes-file RELEASE_NOTES.md
fi