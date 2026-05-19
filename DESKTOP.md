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
- Uses a configurable global hotkey to start and stop dictation. Click the shortcut control and press the key combo you want.
- Records with AVFoundation, sends audio to Hushly's `/transcribe` endpoint, cleans it with `/clean`, then pastes into the app that was focused when dictation started.
- Plays a short system sound on start and stop.
- Lets you edit the tablet text, shortcut, and API base from the app window.
- Copies the final text to the clipboard even if macOS Accessibility permission is not granted.

Default settings:
- Shortcut: `Control + Option + Space`
- Tablet text: `$10k/month`
- API base: `https://hushly-six.vercel.app`

Permissions:
- Microphone permission is required to record.
- Accessibility permission is required for automatic paste into other apps. Without it, Hushly still copies the final text to the clipboard.
- For auto-paste, focus the target text box first and start dictation with the global shortcut. The in-app Dictate button is mainly a settings/test control.

Storage:
- The native Mac app stores transcripts locally at `~/Library/Application Support/Hushly/transcripts.json`.
- Saved audio for retry is stored locally under `~/Library/Application Support/Hushly/Audio/`.
- Supabase history is used by the Expo app after sign-in; the native Mac app does not sync to Supabase yet.

Source files:
- `desktop/macos/HushlyLite.swift`
- `desktop/macos/Info.plist`
- `desktop/macos/Assets/tablet-glow.png`
- `scripts/build-macos-app.sh`
