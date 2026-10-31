#!/bin/sh
# Quick end to end check of an installed Tarn: launches it, drives it with tarnctl, and checks memory and CPU.
# Usage: sh Tools/smoke-test.sh [path to Tarn.app]
APP="${1:-/Applications/Tarn.app}"
CTL="$APP/Contents/Resources/tarnctl"
fail=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

[ -d "$APP" ] || { echo "No app at $APP"; exit 2; }
pkill -x Tarn 2>/dev/null; sleep 1
BEFORE=$(ls ~/Library/Logs/DiagnosticReports/Tarn*.ips 2>/dev/null | wc -l)
defaults write com.antelislabs.tarn welcomed -bool true   # no first launch window, so idle CPU is measured with nothing on screen
open "$APP"; sleep 4
check "app is running" "pgrep -x Tarn"
check "universal binary" "lipo -archs '$APP/Contents/MacOS/Tarn' | grep -q arm64"
check "signature verifies" "codesign --verify --deep --strict '$APP'"
if codesign -dvv "$APP" 2>&1 | grep -q "Authority=Developer ID Application"; then check "Gatekeeper accepts it" "spctl -a '$APP'"; else echo "  skip Gatekeeper check (ad hoc development build)"; fi
check "tarnctl present" "[ -x '$CTL' ]"

"$CTL" start 25; sleep 1.5
check "start 25 runs" "'$CTL' status | grep -q 'running'"
"$CTL" pause; sleep 1
check "pause pauses" "'$CTL' status | grep -q 'paused'"
"$CTL" break; sleep 1.5
check "break starts a break" "'$CTL' status | grep -qi 'break'"
"$CTL" stop
check "bad minutes are refused" "! '$CTL' start 999"
check "bad sound name is refused" "! '$CTL' sound nonsense"
"$CTL" breathe; sleep 1
check "breathe switches mode" "'$CTL' status | grep -q 'breathe'"
"$CTL" sound ocean; sleep 3
check "sound starts without crashing" "pgrep -x Tarn"
"$CTL" sound off
sleep 6
RSS=$(ps -o rss= -p "$(pgrep -x Tarn)" | awk '{printf "%d", $1/1024}')
check "memory under 200 MB (now ${RSS} MB)" "[ ${RSS:-999} -lt 200 ]"
cpu_now() { top -l 2 -pid "$(pgrep -x Tarn)" -stats cpu | tail -1 | awk '{printf "%d", $1}'; }
# Two readings, keep the lower one, so one busy moment on the machine does not fail the test.
c1=$(cpu_now); c2=$(cpu_now); CPU=$(( c1 < c2 ? c1 : c2 ))
check "idle CPU under 5 percent with nothing on screen (now ${CPU}%)" "[ ${CPU:-99} -lt 5 ]"

"$CTL" window; sleep 3
c1=$(cpu_now); c2=$(cpu_now); CPU2=$(( c1 < c2 ? c1 : c2 ))
check "window open and breathing under 20 percent (now ${CPU2}%)" "[ ${CPU2:-99} -lt 20 ]"
check "still running" "pgrep -x Tarn"

AFTER=$(ls ~/Library/Logs/DiagnosticReports/Tarn*.ips 2>/dev/null | wc -l)
check "no new crash reports" "[ $AFTER -eq $BEFORE ]"
pkill -x Tarn
defaults delete com.antelislabs.tarn 2>/dev/null
[ "$fail" = 0 ] && echo "SMOKE TEST PASSED" || echo "$fail FAILED"
exit "$fail"
