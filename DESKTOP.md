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

Storage (privacy-first, local-only on Mac):
- The native Mac app keeps **all** transcripts and audio on the user's own machine. Nothing is uploaded to the VPS for storage.
  - Transcripts: `~/Library/Application Support/Hushly/transcripts.json`
  - Audio for retry: `~/Library/Application Support/Hushly/Audio/pending-<uuid>.m4a`
  - Cropped tablet background: `~/Library/Application Support/Hushly/tablet-background.png`
- The VPS sees audio bytes **only in flight** during the Deepgram proxy call (`/transcribe`) and during cleanup (`/clean`). Neither route persists audio or transcripts to Postgres for the desktop app.
- The mobile and web clients (Expo Router) **do** upload audio to `/audio` and transcripts to `/persist` so History works across devices. That is intentional for those surfaces. The Mac app does not use those endpoints.
- What this means for a friend installing the desktop app:
  - Their recordings never leave their Mac except as the in-flight Deepgram request.
  - Disk usage scales with how much audio they keep for retry. Hushly does not currently rotate audio — they can prune `~/Library/Application Support/Hushly/Audio/` manually if it grows.
  - The only shared resource they consume on your VPS is Deepgram/OpenAI quota via the configured API base.

Sharing:
- Share the app bundle or a zipped copy of `dist/macos/Hushly.app`.
- Do not share raw Deepgram or OpenAI API keys. The desktop app calls the API base in settings; by default that is `https://hushly.genflos.com`, where the server-side keys live on the Contabo VPS.
- Anyone using that API base uses the owner's server-side API keys and quota, so keep the app private or add auth/rate limits before wider sharing.

Source files:
- `desktop/macos/HushlyLite.swift`
- `desktop/macos/Info.plist`
- `desktop/macos/Assets/tablet-glow.png`
- `scripts/build-macos-app.sh`
