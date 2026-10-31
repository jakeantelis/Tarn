# Tarn

A tarn is a small, still mountain lake, quiet enough to hold the sky. Tarn is a calm Mac menu bar app for focus and for breathing: work in focused rounds, then breathe like still water.

![Tarn: focus, a breathing break, breathe and sounds](docs/images/hero.png)

Free and open source. No account, no tracking, and it only goes online when you press Check for updates.

<p align="center"><img src="docs/images/tour.gif" alt="A tour of Tarn: welcome, Focus, a break, Breathe, sounds, stats and settings" width="300"></p>

<p align="center"><img src="docs/images/breathe.gif" alt="The breathing picture opening and closing, as a flower and as water" width="420"></p>

## What it does

**Focus.** Pomodoro rounds of 15, 25, 45, 60 or 90 minutes with calm, timed breaks. A glowing circle narrows as time runs out, dots show your place in the set, and a break opens into a gentle breathing guide that waits until you are ready. Click the circle to start or pause. Choose from ten color themes, keep daily stats, and set a daily schedule so rounds and breaks run on their own between two times.

**Breathe.** A slow breathing picture, a flower or water, with four rhythms (Settle, Deep, Box and 4 7 8), optional written prompts and sessions from 1 to 20 minutes. It plays a soft sound by default, which one switch turns off. While you breathe the controls fade and the picture grows to fill the window.

**Calm mode.** One button for full screen, your last sound mix and Hide other apps, which only hides and never quits anything. Click anywhere or press Esc to return, and the sound fades out as your cue to get back. One switch in Settings turns full screen and hiding off completely.

**Sounds.** Recorded ambient loops (ocean, forest, birds and stream) with presets, a mixer and a fade out timer. Focus is silent until you turn sounds on.

**Built to stay out of the way.** Lives in the menu bar as a small flower. No account, no tracking, and no network use except when you press Check for updates. It never speaks, and it never covers your screen unless you ask.

### A closer look

| Focus | Running | Break |
|---|---|---|
| ![Focus, ready](docs/images/focus-ready.png) | ![Focus, running](docs/images/focus-running.png) | ![A breathing break](docs/images/break.png) |

| Breathe, flower | Breathe, water | Sounds |
|---|---|---|
| ![Breathe, flower](docs/images/breathe-flower.png) | ![Breathe, water](docs/images/breathe-water.png) | ![Sounds](docs/images/sounds.png) |

| Focus settings | Breathe settings | General |
|---|---|---|
| ![Focus settings](docs/images/settings-focus.png) | ![Breathe settings](docs/images/settings-breathe.png) | ![General settings](docs/images/settings-general.png) |

macOS only for now. Timer, breathing and sound logic is kept apart from the interface, so other platforms stay possible later.

See [docs/MANUAL.md](docs/MANUAL.md) for the manual and FAQ. There is also a searchable Help inside the app.

## Install
1. Download `Tarn.dmg` from the [latest release](https://github.com/jakeantelis/Tarn/releases/latest) and open it.
2. Move Tarn into Applications. The easy way: double click Tarn and choose Move to Applications, and Tarn moves itself, opens and ejects the disk image. Or drag Tarn onto Applications yourself and open it from there. Keep Tarn in Applications, because it will not keep working if you run it from the disk image.
3. Look for the small flower in your menu bar.

Tarn needs macOS 14 or later and runs on Apple silicon and Intel. If a crowded menu bar or the notch hides the icon, turn on "Show Tarn in the Dock" in Settings, or run `tarnctl window`. On the first launch Tarn also opens a window.

**Updates.** Open Settings, General and press Check for updates. Tarn never checks by itself.

## Command line
In the app, open Settings, General and press Install tarnctl (no password needed). From a source checkout, `Tools/install-cli.sh` does the same.

```
tarnctl start 45        start a 45 minute round
tarnctl pause           pause (tarnctl resume continues)
tarnctl break           start a break now
tarnctl breathe full    open Breathe in full screen
tarnctl calm            full screen, sound and Hide other apps
tarnctl sound forest    play a sound preset
tarnctl clear           hide other windows (restore brings them back)
tarnctl status          show what Tarn is doing
tarnctl window          open Tarn in a normal window
```

It talks to the app through `tarn://` links, so Shortcuts and Raycast can use them too. Any web page can open a `tarn://` link, so these links can only start, pause or stop timers, hide windows or open full screen breathing. They cannot read files or run anything. You can switch them off in Settings.

## Build
`./build.sh` builds `build/Tarn.app`. Add `run` to launch it. `Tools/run-tests.sh` runs the logic tests, and `Tools/release.sh` builds a universal app, signs it, notarizes it and makes the DMG.

## Sounds and credits
Every sound is CC0 or self made. See [SOURCES.md](SOURCES.md) for the source, license and link of each file. The recorded loops come from BigSoundBank.

## License
MIT. See [LICENSE](LICENSE).
