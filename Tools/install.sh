#!/bin/sh
set -eu

# Installs Tarn.
#
#   curl -fsSL https://raw.githubusercontent.com/jakeantelis/Tarn/main/Tools/install.sh | sh
#   sh Tools/install.sh --dmg dist/Tarn.dmg      (install from a local file, for testing)
#
# Downloads the latest release, checks its SHA-256, installs to /Applications
# (or ~/Applications), links the tarnctl command and opens Tarn.

REPO="jakeantelis/Tarn"
LATEST="https://github.com/$REPO/releases/latest/download"
DMG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dmg) DMG="${2:-}"; shift 2 || { echo "--dmg needs a file" >&2; exit 1; } ;;
        --help|-h)
            echo "Usage: install.sh [--dmg path/to/Tarn.dmg]"
            exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

OS=$(sw_vers -productVersion 2>/dev/null || echo "0")
MAJOR=$(printf '%s' "$OS" | cut -d . -f 1)
if [ "$MAJOR" -lt 14 ] 2>/dev/null; then
    echo "Tarn needs macOS 14 or newer. This Mac has $OS." >&2
    exit 1
fi

DEST="/Applications"
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi

TMP=$(mktemp -d)
MNT=""
cleanup() {
    [ -n "$MNT" ] && hdiutil detach "$MNT" -quiet 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT

SRC=""
if [ -n "$DMG" ]; then
    [ -f "$DMG" ] || { echo "Can't find $DMG" >&2; exit 1; }
    MNT="$TMP/mnt"
    mkdir -p "$MNT"
    hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MNT"
    SRC="$MNT/Tarn.app"
else
    echo "Downloading the latest release..."
    if ! curl -fsSL "$LATEST/Tarn.zip" -o "$TMP/Tarn.zip" || ! curl -fsSL "$LATEST/Tarn.zip.sha256" -o "$TMP/Tarn.zip.sha256"; then
        echo "Couldn't download Tarn. Check your connection and try again." >&2
        exit 1
    fi
    WANT=$(awk '{print $1}' "$TMP/Tarn.zip.sha256")
    GOT=$(shasum -a 256 "$TMP/Tarn.zip" | awk '{print $1}')
    if [ "$WANT" != "$GOT" ]; then
        echo "The download did not match its checksum, so nothing was installed." >&2
        exit 1
    fi
    ditto -x -k "$TMP/Tarn.zip" "$TMP/unzipped"
    SRC="$TMP/unzipped/Tarn.app"
fi

[ -d "$SRC" ] || { echo "Tarn.app was not found in the download." >&2; exit 1; }
codesign --verify --deep --strict "$SRC" 2>/dev/null || { echo "The app's signature did not verify, so nothing was installed." >&2; exit 1; }

if pgrep -x Tarn >/dev/null 2>&1; then
    echo "Closing the running Tarn..."
    pkill -x Tarn 2>/dev/null || true
    n=0; while pgrep -x Tarn >/dev/null 2>&1 && [ "$n" -lt 30 ]; do sleep 0.1; n=$((n + 1)); done
fi

rm -rf "$DEST/Tarn.app"
ditto "$SRC" "$DEST/Tarn.app"

# Link the command line tool where a shell can find it. No password needed.
mkdir -p "$HOME/.local/bin"
ln -sf "$DEST/Tarn.app/Contents/Resources/tarnctl" "$HOME/.local/bin/tarnctl"

echo "Installed Tarn to $DEST."
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "To use tarnctl, add ~/.local/bin to your PATH." ;;
esac
open "$DEST/Tarn.app"
echo "Tarn is open. Look for the small flower in your menu bar."
