# Tarn on the Mac App Store

The Store edition is the same source with `APPSTORE` defined. Build it with `Tools/build-appstore.sh`.

## What differs from the direct download
- Runs in the App Sandbox (`Resources/Tarn-AppStore.entitlements`: sandbox only; no network, no file access).
- No Sparkle and no network use. The Store delivers updates; the Sparkle keys are removed from Info.plist.
- No "Move to Applications" offer and no tarnctl installer (the sandbox blocks both). `tarn://` links still work.
- "Run a Shortcut" uses Shortcuts' own link instead of running `/usr/bin/shortcuts`.
- Universal (arm64 and x86_64), macOS 14 or later.

## Still to do before submitting
1. In the Apple developer account (team 6G8C59T679), create the two Mac App Store certificates
   ("Mac App Store Distribution" application and "Mac Installer Distribution") and a Mac App Store
   provisioning profile for `com.antelislabs.tarn.ios`. Done 2026-11-23: certificates installed, profile "Tarn Mac AppStore iOS ID".
2. The Mac app is the macOS platform added to the existing iPhone record (Apple ID 6829876417), so the Store build uses the iPhone bundle ID `com.antelislabs.tarn.ios` and version 1.0 (`Tools/build-appstore.sh` sets both). The direct download keeps `com.antelislabs.tarn`.
3. Run the signed build:
   `TARN_MAS_APP_ID=... TARN_MAS_INSTALLER_ID=... TARN_MAS_PROFILE=... Tools/build-appstore.sh`, then upload `dist/Tarn-AppStore.pkg` with Transporter.
4. Test the sandboxed build by hand first (open `build/Tarn-AppStore.app`): launch at login, notifications, sound,
   Breathe full screen, hiding other apps, and a Shortcut run. Hiding other apps and the Shortcuts link are the two
   most likely to behave differently in the sandbox.
5. Listing: Mac screenshots, privacy label ("Data not collected"), age rating, and a review note that the app
   has no account and nothing to sign in to. Same review-proof lesson as the iPhone app: test with every permission prompt declined.
