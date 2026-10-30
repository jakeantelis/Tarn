# Stillwater

Native macOS menu bar app: Work, Study and Relax in one. macOS only for now.
Build: `./build.sh` (add `run` to launch). Timer (`PomodoroTimer.swift`), breathing math (`BreathPattern` in `BreathingView.swift`) and sound synthesis (`SoundGenerator` in `SoundEngine.swift`) are kept separate from the SwiftUI views so other platforms stay possible later.

## Modes
- **Pomodoro:** timed focus rounds (Classic 25/5/15, Deep 50/10/20, or Custom). Breaks open into guided breathing by default.
- **Breathe:** a calm bloom animation with optional ambient sound, no timer. Use it on its own any time.

Sound is off by default (Settings turns it on, and can limit it to focus or breaks). Spoken breathing cues are optional, off by default, and use the Mac's built in offline voice.
