#!/bin/zsh
set -euo pipefail
setopt nullglob
cd "$(dirname "$0")"

APP=build/Tarn.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SPARKLE=$(Tools/fetch-sparkle.sh)

echo "Compiling..."
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift \
    -o "$APP/Contents/MacOS/Tarn" \
    -framework SwiftUI -framework AppKit -framework AVFoundation -framework UserNotifications \
    -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks

Tools/embed-sparkle.sh "$SPARKLE" "$APP" -

mkdir -p "$APP/Contents/Resources/Sounds"
cp Resources/Sounds/*.{wav,caf,m4a} "$APP/Contents/Resources/Sounds/" 2>/dev/null || true
mkdir -p "$APP/Contents/Resources/Voice"
cp Resources/Voice/*.m4a "$APP/Contents/Resources/Voice/" 2>/dev/null || true
cp Tools/tarnctl "$APP/Contents/Resources/tarnctl"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" 2>&1 || echo "warning: ad-hoc codesign failed" >&2   # Sparkle inside was signed first
echo "Built $APP"
[[ "${1:-}" == "run" ]] && open "$APP"
