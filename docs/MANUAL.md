# Tarn manual and FAQ

A tarn is a small, still mountain lake. Tarn is a calm place to focus, and to breathe.


## Getting started

**What is Tarn?**  
A calm Mac menu bar app. Focus runs timed work rounds with breaks. Breathe is a slow breathing animation. Sounds are optional. It is free, with no account and no tracking.

**How do I start a round?**  
Click the big circle, or press Start. Tap the length pill under it to choose 15, 25, 45, 60 or 90 minutes.

**What does the length pill mean?**  
The small pill under the circle is the length of one focus round. Tap it to change it. The dots inside the circle show your rounds: a filled dot is finished and a ring is the one you are on. After the last dot you get a longer break.

**What happens on a break?**  
The picture changes to a gentle breathing guide and the window turns soft purple. When the break ends, the next round starts on its own unless you turn that off in Settings.


## Floating circle
A small frosted circle stays above your other windows. In Focus it shows the time, and in Breathe it shows the breathing picture. Click it to start or pause, hover for a sound button, and drag it anywhere. Close it with the X, or right click it for more. Change its size, or turn it off, in Settings, Focus, or from the three dots menu. It steps aside in full screen.

## Breathe

**How do I use Breathe?**  
Switch to Breathe. Breathe in as the picture opens and out as it closes. Click the picture to pause it.

**What are Settle, Deep, Box and 4 7 8?**  
Settle starts easy and slowly deepens over three minutes. Deep is in for 6, hold 2, out for 8. Box is in 4, hold 4, out 4, hold 4. 4 7 8 is in for 4, hold 7, out for 8.

**What does Full screen do?**  
It covers every screen with a calm background, including desktop icons. Click anywhere, press Esc, or use the Close button to go back. The sound buttons in the top right corner turn sound on or off and pick a mix.

**What is Calm mode?**  
One button for full screen, your last sound mix and Hide apps. When you leave, the sound fades out as a quiet cue that it is time to get back, unless you choose to keep it playing in Settings. Add two Shortcuts in Settings if you also want Do Not Disturb.

**Where did the controls go?**  
While you breathe and the mouse is still, the controls fade so only the picture and the word remain. Move the mouse and they come back. The Options menu holds the session length, the look and the sound, including a full sound mixer.

**What is a Session?**  
Choose the Session length under the pattern buttons: 1, 3, 5, 10 or 20 minutes, or Open to keep going. When it ends, any sound you have on fades out, which is your quiet cue that it is time to get back. You can keep it playing in Settings. It works as a simple meditation timer too.

**Is there always a voice?**  
No. Breathe and its sessions are quiet. The voice only plays when you choose one: use the Guided meditation button under Calm mode on the Breathe screen, or Options, under "Guided meditation, with a voice". If you never use it, switch off "Offer guided meditation" in Settings, under Breathe, and the button and menu items go away.

**How does guided meditation work?**  
In Breathe, click Guided meditation under Calm mode (or open Options) and choose 5, 10 or 20 minutes. Pick a voice in the same menu: Soft, Warm or Grounded. It starts with a few quiet seconds to get comfortable while the welcome is spoken, then the picture begins with the Settle rhythm. The line under the picture shows what the voice is saying, with time left below. Click the picture to pause the voice and the breath together, or choose End meditation in Options.

**What happens to the sound in a guided meditation?**  
Your sound mix plays softly underneath, or Ocean calm if you have none. Turn that off in Settings, under Breathe. Sound that started for the meditation fades out slowly over 30 seconds when it ends. Under Sounds afterwards you can let it stay for 3 or 10 minutes first. Sound you had on already goes back to its normal level.

**I cannot hear the voice.**  
If the Mac is muted or the volume is almost all the way down, Tarn shows a quiet line: Volume is low. Turn it up to hear the voice.

**What does Hide apps do?**  
It hides other apps' windows so you can breathe. It never quits anything. Press Bring back, or start a focus round, and they return.


## Sounds

**How do I turn sounds on?**  
In Focus, open the Sounds tab. In Breathe, open Options, then Sound or Mix sounds. Pick a preset or move a slider. Up to three sounds play at once. A fade out timer can stop them for you, with a slow 30 second fade. Focus is silent until you turn sounds on. Breathe plays a soft sound by default, and you can switch it off in Settings, under Breathe.


## Good to know

**I cannot find the icon.**  
On some Macs the notch or a crowded menu bar hides it. Open Settings, then Open in a window, or turn on Show Tarn in the Dock.

**Does Tarn collect anything?**  
No. Everything stays on your Mac, including your stats.

**Which Macs does it support?**  
macOS 14 or later, on Apple silicon and Intel.

**Can I control it from Terminal?**  
Yes. Run tarnctl, for example tarnctl start 45 or tarnctl breathe full.


## Make it yours
Settings opens in its own roomy window with a sidebar: Focus, Breathe, General and this help. From Terminal, `tarnctl settings` opens it too.

Everything in Settings is optional. Breaks do not take over your screen unless you turn that on, so you can watch a video or read during a break. In Breathe settings, "Allow full screen and hiding apps" is one switch: turn it off and Tarn never covers your screen or hides another app, and those buttons disappear. Otherwise you can keep Hide apps and Full screen as buttons you press only when you want them, switch the sound offer off, pick your own colors, set your own focus length, and open Tarn in a window or the Dock if you prefer.

## Requirements and caveats
- macOS 14 (Sonoma) or later, on Apple silicon and Intel. Built and tested on macOS 27; older versions are expected to work but have not been tested on hardware.
- Tarn needs no special permissions. It does not use the microphone, camera or location. It uses the network only when you press Check for updates in Settings, General, which asks GitHub for the newest version and sends nothing about you.
- Hide apps uses the same hide as the Cmd+H shortcut. It never quits an app and never closes a document.
- The Focus Shortcut hooks run the Shortcuts you name, so they can do anything a Shortcut can. Leave them blank if you do not use them.
- The optional round reminder asks macOS for permission to show a quiet banner. Nothing is sent anywhere.
- Tarn follows the Mac setting Reduce Motion by holding the flower still and skipping the ripples.
- Any web page can open a tarn:// link, and you can switch tarnctl and links off in Settings. Those links can only start or stop timers, hide windows or open full screen breathing.
- The recorded sounds are public domain (CC0) from BigSoundBank. See SOURCES.md.

## Help and tips

Click Help along the bottom of the Tarn window to open the searchable FAQ (also Settings, Help and FAQ). Tips are short hints at the bottom of the window. They are off by default and switch on in Settings, General.

## Updates

Open Settings, General, Updates and press Check for updates. Tarn never checks by itself. If a newer version exists, press Download, then drag the new Tarn over the old one in Applications.
