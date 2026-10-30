#!/bin/zsh
set -euo pipefail
# Links stillwaterctl onto your PATH. Uses ~/.local/bin so no password is needed.
SRC="/Applications/Stillwater.app/Contents/Resources/stillwaterctl"
[[ -x "$SRC" ]] || SRC="$HOME/Applications/Stillwater.app/Contents/Resources/stillwaterctl"
[[ -x "$SRC" ]] || { echo "Stillwater.app not found in Applications." >&2; exit 1; }
mkdir -p "$HOME/.local/bin"
ln -sf "$SRC" "$HOME/.local/bin/stillwaterctl"
echo "Linked ~/.local/bin/stillwaterctl"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Add ~/.local/bin to your PATH to use it." ;; esac
