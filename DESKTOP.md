# hushly desktop app

The repo includes a no-new-dependencies native macOS dictation app:

```bash
cd "/Users/jerel/CC Apps/hushly"
scripts/build-macos-app.sh
open dist/macos/Hushly.app
```

What it does:
- Runs as a small menu-bar app with a draggable glowing tablet overlay.
- Uses a configurable global hotkey to start and stop dictation.
- Records with AVFoundation, sends audio to Hushly's `/transcribe` endpoint, cleans it with `/clean`, then pastes into the app that was focused when dictation started.
- Plays a short system sound on start and stop.
- Lets you edit the tablet text, shortcut, and API base from **Settings**.
- Copies the final text to the clipboard even if macOS Accessibility permission is not granted.

Default settings:
- Shortcut: `Control + Option + Space`
- Tablet text: `$10k/month`
- API base: `https://hushly-six.vercel.app`

Permissions:
- Microphone permission is required to record.
- Accessibility permission is required for automatic paste into other apps. Without it, Hushly still copies the final text to the clipboard.

Source files:
- `desktop/macos/HushlyLite.swift`
- `desktop/macos/Info.plist`
- `desktop/macos/Assets/tablet-glow.png`
- `scripts/build-macos-app.sh`
