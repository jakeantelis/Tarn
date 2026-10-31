#!/bin/zsh
# Compiles the app sources (without the app entry point) with the logic tests and runs them.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
export TARN_STATUS_DIR="$out/status"   # keep test runs away from the real app's status file
ls Sources/*.swift | grep -v TarnApp | xargs swiftc -O -swift-version 5 -parse-as-library Tests/LogicTests.swift \
    -o "$out/tests"
TARN_SECONDS_PER_MINUTE=1 "$out/tests" -framework SwiftUI -framework AppKit -framework AVFoundation -framework ServiceManagement -framework UserNotifications
"$out/tests"
TARN_SECONDS_PER_MINUTE=1 "$out/tests"
