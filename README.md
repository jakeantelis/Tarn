# Tarn

A tarn is a small, still mountain lake. Tarn is a calm Mac menu bar app for focus and for breathing.

Free and open source. No account, no tracking. Made by Antelis Labs.

## What it does
- **Focus:** Pomodoro rounds (15, 25, 45, 60 or 90 minutes) with calm, timed breaks. A focus lens tightens as time runs out, and breaks open into guided breathing. Optional schedule, daily stats and an intention line.
- **Breathe:** a slow breathing animation as a flower, water or ripples, with gentle prompts and an optional spoken guide. Full screen mode and a button to hide other apps (it never quits them).
- **Sounds:** optional recorded ambient loops (ocean, forest, birds, stream) with presets and a fade out timer. Everything is off until you turn it on.

macOS only for now. Timer, breathing and sound logic is kept apart from the interface so other platforms stay possible later.

## Build
`./build.sh` builds `build/Tarn.app`. Add `run` to launch it.

## Command line
`Tools/install-cli.sh` links `tarnctl` onto your PATH. Examples: `tarnctl start 45`, `tarnctl break`, `tarnctl breathe full`, `tarnctl sound forest`, `tarnctl clear` (hides other windows, never quits apps), `tarnctl restore`, `tarnctl status`, `tarnctl window` (open Tarn in a normal window). It talks to the app through `tarn://` links, so Shortcuts and Raycast can use them too.

## Release
`Tools/release.sh` builds a universal app, signs, notarizes and makes a DMG.

## Sounds and credits
Every sound is CC0 or self made. See `SOURCES.md` for the source, license and URL of each file.

## License
MIT. See `LICENSE`.
