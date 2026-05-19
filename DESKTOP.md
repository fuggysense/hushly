# hushly desktop app — strategy

You asked about turning the web app into a desktop app. Three real paths, ranked by fit for a dictation tool that needs a global hotkey + the ability to insert text into the active text field of any other app:

## 1. Tauri (recommended)

Native, tiny binary (~6MB), uses the OS's webview so we just point it at our Expo Web bundle. Critical wins for hushly:

- **Global system hotkey** via `tauri-plugin-global-shortcut` — press `⌃⌥Space` from anywhere to start recording.
- **macOS Accessibility API** via a small Swift sidecar (or `enigo` Rust crate) to type the cleaned text into the **frontmost app's text field** — the same UX as Wispr Flow / Superwhisper on Mac.
- **Menubar app** via `tauri-plugin-positioner` — small icon, no Dock presence.
- **App distribution** is a notarized `.app` you can drop on a download page; no App Store needed.
- **Auto-update** via `tauri-plugin-updater`.

Build:
```bash
cd "/Users/jerel/CC Apps/hushly"
# Add Tauri to the existing Expo project
npm install --save-dev @tauri-apps/cli @tauri-apps/api
npx tauri init   # answers: dev URL = http://localhost:8081, dist dir = dist/client
npm install tauri-plugin-global-shortcut-api
npx tauri dev    # builds and launches the native window
```

Then write the Rust glue in `src-tauri/src/main.rs` to:
1. Register the global hotkey.
2. On hotkey: bring the hushly window to front OR record silently.
3. After /clean returns: paste into frontmost app via `enigo::Enigo::text(&cleaned)` (cross-platform) OR a macOS-specific `CGEventKeyboardSetUnicodeString` for reliability.

~1 day of work to ship a working menubar dictation app.

## 2. Electron

Heavier (~150MB), slower startup, more memory. The Wispr Flow / Superwhisper desktop apps are Electron. Same capabilities as Tauri but heavier. Pick this only if you already know Electron well.

## 3. PWA (install from browser)

Simplest. Open https://hushly-six.vercel.app in Chrome/Edge → "Install hushly". Becomes a standalone window. **But:**
- No global hotkey outside the app window.
- No text injection into other apps' fields — only clipboard hop.
- Clipboard requires the window to be focused.

Use this as Day-1 shipping, then build Tauri for Day-30. Most users won't switch from Cmd-V to a hotkey-driven Tauri app until they're already addicted to the workflow.

## Recommended path

**Ship the PWA first** (literally just add `manifest.json` to `dist/client/`, takes 30 min). **Build Tauri after the keyboard extension** because Tauri reuses your existing Vercel + Supabase + Deepgram + Haiku stack — no API changes needed, just a thin native shell.

The keyboard extension and the Tauri desktop app are independent products that share the same backend.
