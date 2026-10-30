#!/bin/zsh
set -euo pipefail
# Links tarnctl onto your PATH. Uses ~/.local/bin so no password is needed.
SRC="/Applications/Tarn.app/Contents/Resources/tarnctl"
[[ -x "$SRC" ]] || SRC="$HOME/Applications/Tarn.app/Contents/Resources/tarnctl"
[[ -x "$SRC" ]] || { echo "Tarn.app not found in Applications." >&2; exit 1; }
mkdir -p "$HOME/.local/bin"
ln -sf "$SRC" "$HOME/.local/bin/tarnctl"
echo "Linked ~/.local/bin/tarnctl"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Add ~/.local/bin to your PATH to use it." ;; esac
