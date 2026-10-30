#!/bin/sh
set -eu

# Removes Tarn.
#
#   sh Tools/uninstall.sh            remove the app and the tarnctl link
#   sh Tools/uninstall.sh --purge    also remove saved settings, stats and caches
#   sh Tools/uninstall.sh --yes      do not ask first

YES=0; PURGE=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y) YES=1 ;;
        --purge) PURGE=1 ;;
        --help|-h) echo "Usage: uninstall.sh [--yes] [--purge]"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

if [ "$YES" = 0 ]; then
    printf "Remove Tarn? [y/N] " >&2
    answer=""; read -r answer || true
    case "$answer" in y|Y|yes|YES) ;; *) echo "Cancelled."; exit 0 ;; esac
fi

if pgrep -x Tarn >/dev/null 2>&1; then
    echo "Closing Tarn..."
    pkill -x Tarn 2>/dev/null || true
    n=0; while pgrep -x Tarn >/dev/null 2>&1 && [ "$n" -lt 30 ]; do sleep 0.1; n=$((n + 1)); done
fi

for d in /Applications "$HOME/Applications"; do
    [ -d "$d/Tarn.app" ] && { rm -rf "$d/Tarn.app"; echo "Removed $d/Tarn.app"; }
done
LINK="$HOME/.local/bin/tarnctl"
[ -L "$LINK" ] && { rm -f "$LINK"; echo "Removed $LINK"; }

if [ "$PURGE" = 1 ]; then
    defaults delete com.antelislabs.tarn 2>/dev/null || true
    rm -rf "$HOME/Library/Application Support/Tarn" "$HOME/Library/Caches/com.antelislabs.tarn" \
           "$HOME/Library/Preferences/com.antelislabs.tarn.plist" "$HOME/Library/Saved Application State/com.antelislabs.tarn.savedState"
    echo "Removed settings, stats and caches."
fi
echo "Tarn is removed. If you turned on Open at login, it disappears from Login Items by itself."
