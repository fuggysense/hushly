# hushly desktop app

The repo includes a no-new-dependencies native macOS dictation app:

```bash
cd "/Users/jerel/CC Apps/hushly"
scripts/build-macos-app.sh
open dist/macos/Hushly.app
```

What it does:
- Runs as a small native Mac app with a Dock icon, a normal settings/control window, and a menu-bar helper.
- Opens settings from the Dock icon, the app menu, or the menu-bar helper.
- The settings window can be minimized like a normal Mac window.
- Shows a local History tab with timestamped transcripts, copy, and retry for entries with saved audio.
- Shows a much smaller draggable glowing tablet overlay only while dictating.
- Lets you choose a rectangle or circle tablet, set the border color, upload a PNG/JPEG, crop it with preview controls, clear it, and toggle tablet text on/off.
- Uses a configurable global hotkey to start and stop dictation. Click the shortcut control and press the key combo you want.
- Records with AVFoundation, sends audio to Hushly's `/transcribe` endpoint, cleans it with `/clean`, then pastes into the app that was focused when dictation started.
- Plays a short system sound on start and stop.
- Lets you edit the tablet text, shortcut, and API base from the app window.
- Copies the final text to the clipboard even if macOS Accessibility permission is not granted.

Default settings:
- Shortcut: `Control + Option + Space`
- Tablet text: `$10k/month`
- API base: `https://hushly.genflos.com`

Permissions:
- Microphone permission is required to record.
- Accessibility permission is required for automatic paste into other apps. Without it, Hushly still copies the final text to the clipboard.
- For auto-paste, focus the target text box first and start dictation with the global shortcut. The in-app Dictate button is mainly a settings/test control.

Storage:
- The native Mac app stores transcripts locally at `~/Library/Application Support/Hushly/transcripts.json`.
- Saved audio for retry is stored locally under `~/Library/Application Support/Hushly/Audio/`.
- Custom tablet images are cropped and stored locally at `~/Library/Application Support/Hushly/tablet-background.png`.
- Hushly web history is stored in the VPS Postgres database after sign-in; the native Mac app does not sync to the VPS database yet.

Sharing:
- Share the app bundle or a zipped copy of `dist/macos/Hushly.app`.
- Do not share raw Deepgram or OpenAI API keys. The desktop app calls the API base in settings; by default that is `https://hushly.genflos.com`, where the server-side keys live on the Contabo VPS.
- Anyone using that API base uses the owner's server-side API keys and quota, so keep the app private or add auth/rate limits before wider sharing.

Source files:
- `desktop/macos/HushlyLite.swift`
- `desktop/macos/Info.plist`
- `desktop/macos/Assets/tablet-glow.png`
- `scripts/build-macos-app.sh`
