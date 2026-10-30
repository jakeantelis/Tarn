# Stillwater

Native macOS menu bar app: Work, Study and Relax in one. macOS only for now.
Build: `./build.sh` (add `run` to launch). Timer (`PomodoroTimer.swift`), breathing math (`BreathPattern` in `BreathingView.swift`) and sound synthesis (`SoundGenerator` in `SoundEngine.swift`) are kept separate from the SwiftUI views so other platforms stay possible later.

## Modes
- **Pomodoro:** timed focus rounds (Classic 25/5/15, Deep 50/10/20, or Custom). Breaks open into guided breathing by default.
- **Breathe:** a calm bloom animation with optional ambient sound, no timer. Use it on its own any time.

Sound is off by default (Settings turns it on, and can limit it to focus or breaks). Spoken breathing cues are optional, off by default, and use the Mac's built in offline voice.

## Command line
`Tools/install-cli.sh` links `stillwaterctl` onto your PATH. Examples: `stillwaterctl start 45`, `stillwaterctl break`, `stillwaterctl breathe full`, `stillwaterctl sound rainy`, `stillwaterctl clear` (hides other windows, never quits apps), `stillwaterctl restore`, `stillwaterctl status`. It talks to the app through `stillwater://` links, so Shortcuts and Raycast can use them too.

## Release
`Tools/release.sh` builds a universal app, signs, notarizes and makes a DMG, the same as Matcha.
