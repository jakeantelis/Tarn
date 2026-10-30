#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Stillwater.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling..."
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift \
    -o "$APP/Contents/MacOS/Stillwater" \
    -framework SwiftUI -framework AppKit -framework AVFoundation

mkdir -p "$APP/Contents/Resources/Sounds"
cp Resources/Sounds/*.{wav,caf,m4a} "$APP/Contents/Resources/Sounds/" 2>/dev/null || true
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" 2>&1 || echo "warning: ad-hoc codesign failed" >&2
echo "Built $APP"
[[ "${1:-}" == "run" ]] && open "$APP"
