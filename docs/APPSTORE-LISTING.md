# Tarn for Mac: App Store listing (draft)

Original words. No health claims, no trademarks. Limits are Apple's (name 30, subtitle 30, keywords 100, promo 170).

## Name
Tarn: Focus & Breathe

(The iPhone app is "Tarn: Focus & Breathe". If the Mac name is taken as a separate record, use "Tarn Focus & Breathe".)

## Subtitle (max 30)
Calm timer, breathing, quiet

## Promotional text (max 170)
A calm menu bar companion. Work in focused rounds, then breathe like still water. Free, with no account and no tracking.

## Description
Tarn lives in your menu bar and helps you work in calm, focused rounds and take real breaks.

FOCUS
Set a work round, then a break. Tarn keeps time quietly, with a soft banner when a round ends and an optional floating circle that shows how long is left. Focus itself is silent. You choose the round and break lengths, how many rounds make a set, and what happens between them.

BREATHE
A slow breathing animation that fills the screen, with a gentle rhythm to follow. Pick a length (1 to 20 minutes, or no timer) and a rhythm. Tarn can tidy your screen for you by hiding other apps' windows while you breathe, then bring back exactly the ones it hid. Press Escape to leave at any time.

GUIDED MEDITATION
Prefer a voice? Choose a 5, 10 or 20 minute guided session with a soft, warm or grounded voice. It is optional and never plays unless you ask for it.

SOUNDS
A small mixer of nature sounds (ocean, forest, birds, stream) to play under your work or your breathing. All sounds are included, and Tarn fades them out when a session ends.

YOURS TO SET UP
Open at login, show or hide the Dock icon, choose an app icon, set a Shortcut to run when a session starts, and control Tarn with tarn:// links. A simple stats view shows your rounds over time.

PRIVATE BY DESIGN
No account. No ads. No tracking. Tarn does not go online. Everything stays on your Mac.

Free and open source (MIT). Source: github.com/jakeantelis/Tarn

## Keywords (max 100, comma separated, no spaces after commas)
pomodoro,focus,timer,breathing,calm,meditation,menu bar,breathe,relax,study,productivity,nature sounds

(Do not repeat words from the name; "focus" and "breathe" are already in the name, so you can swap them for "mindful,concentration,break,routine" if you want more reach.)

## What's New (1.0)
First release on the Mac App Store. Focus rounds, breathing, guided meditation and nature sounds, all in your menu bar. Free, private, no account.

## Categories
Primary: Productivity. Secondary: Health & Fitness (or Lifestyle).

## Support / marketing / privacy URLs
Support: https://github.com/jakeantelis/Tarn/issues (or a page on antelislabs.com)
Privacy policy: needs a URL; reuse the iPhone app's.

## Age rating
4+. No objectionable content, no web access, no purchases.

## Privacy label ("App Privacy" in App Store Connect)
Data Not Collected. (Tarn has no network access, no analytics, no accounts. Stats stay in the app's own sandbox container.)

## Price
Free.

## Review notes
Tarn has no account, no sign-in and no in-app purchases, so there is nothing to log in to. It is a menu bar app: after launch, click the flower icon in the menu bar. Focus runs a timer; Breathe plays a slow breathing animation; "Guided meditation" under Calm mode plays a spoken session. Notifications are optional and the app works with the permission declined. "Hide other apps while breathing" only hides windows with the standard NSRunningApplication.hide and restores them afterwards; it can be turned off in Settings > Breathe. The app makes no network connections. The open-source code is at github.com/jakeantelis/Tarn.

## Screenshots (Mac)
Accepted sizes: 1280x800, 1440x900, 2560x1600, 2880x1800 (16:10), 1 to 10 images. Suggested set: Focus screen, Breathe full screen, Guided meditation, Settings, Stats. Captured from the sandboxed build at 2560x1600 in `docs/appstore-screenshots/` (1-focus, 2-breathe, 3-settings, 4-general, 5-fullscreen). The focus shot shows a timer mid-round; retake after any UI change.

---

# What Jake has to do (in order)

1. developer.apple.com > Account > Certificates, IDs & Profiles > Certificates > "+":
   a. "Mac App Distribution" (shows as "3rd Party Mac Developer Application"). Needs a CSR from Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority (save to disk). Download and double click to install.
   b. "Mac Installer Distribution" ("3rd Party Mac Developer Installer"). Same CSR works. Download and install.
2. Identifiers: confirm `com.antelislabs.tarn` exists (Identifiers > App IDs > macOS). If not, "+" > App IDs > App > macOS, Explicit, `com.antelislabs.tarn`. No capabilities needed.
3. Profiles > "+" > Distribution > "Mac App Store Connect" > App ID `com.antelislabs.tarn` > select the Mac App Distribution certificate > name it "Tarn Mac AppStore" > Generate > Download.
4. appstoreconnect.apple.com > Apps > "+" > New App > Platform macOS, name, language, bundle ID `com.antelislabs.tarn`, SKU (e.g. tarn-mac). Fill in the listing from this file, the privacy label, age rating, price Free.
5. Tell me (or the next session) the certificate names (`security find-identity -v` will show them) and the profile path. I will then run the signed build, make the .pkg, and Jake uploads with Transporter. No push or upload happens without his go.
