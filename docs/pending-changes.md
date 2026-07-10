# Pending Changes

This file tracks local changes that have not been shipped through Sparkle.

## 2026-07-10

### Don't interrupt earpiece music: never auto-open a Bluetooth mic

- Status: local only, not shipped to Sparkle. No server changes.
- Major-change count: 1 (capture never forces a Bluetooth earpiece into call mode on its own).
- Scope: `desktop/macos/AudioCapture.swift`, `desktop/macos/HushlyLite.swift`.
- Why: on macOS, normal recording does not pause other apps' audio — the one exception is Bluetooth. Opening a Bluetooth headset's *microphone* forces it from A2DP (stereo playback) into HFP/SCO (mono call mode), which cuts/degrades music playing on that same earpiece. USB/built-in mics are separate HAL devices and never touch the earpiece. (Confirmed by probe: the DJI "Wireless Mic Rx" is USB, so the current AirPods-out + DJI-in setup already never interrupts music.)
- Change:
  - `AudioDeviceManager` gains `transportType()`, `isBluetooth()`, `defaultInputDeviceID()`, and `resolveCaptureUID(selected:)`. The resolver respects an explicit mic selection (the user asked for it, Bluetooth or not) but, in **System default** mode, if the default input is a Bluetooth earpiece it falls back to the first non-Bluetooth input — so Hushly never silently grabs the earpiece mic and kills playback.
  - Both capture paths (`EngineRecorder.start`, `RealtimeSession.start`) now pass the resolved UID instead of the raw preference.
- Verified: build clean (no warnings), `codesign --verify --deep --strict` passes, `tsc --noEmit` clean, lint unchanged (1 pre-existing warning). Runtime-probed transport types: Wireless Mic Rx = `usb`, MacBook Pro Microphone = `bltn`, all `bluetooth=false`; `resolveCaptureUID("")` → "" (safe default), `resolveCaptureUID(WirelessMicRx)` → the DJI USB device.
- Reversible by: reverting the git commit that contains this entry and the matching file changes.
- Sparkle approval: not requested.

### Output device selection (system default output picker)

- Status: local only, not shipped to Sparkle. No server changes.
- Major-change count: 1 (pick the system audio output device from Settings).
- Scope: `desktop/macos/AudioCapture.swift`, `desktop/macos/HushlyLite.swift`.
- Change:
  - `AudioDeviceManager` gains `outputDevices()` (enumerates CoreAudio devices with output streams via a new `hasOutputStreams` scope-output check; excludes input-only), `defaultOutputDeviceUID()`, and `setDefaultOutputDevice(uid:)` (flips `kAudioHardwarePropertyDefaultOutputDevice`). New `AudioOutputDevice` struct parallels `AudioInputDevice`.
  - Settings pane gains an **Output** popup directly above **Microphone**. Unlike the mic picker, there is **no stored preference** — the OS default output is the single source of truth, so the popup preselects the live system default and selecting an entry flips the system default output (mirrors macOS Sound). This lets you keep AirPods as your listening device while a separate mic (e.g. "Wireless Mic Rx") feeds capture, all from one place. If the chosen device vanished between listing and selecting, `setDefaultOutputDevice` returns false and the popup resyncs.
  - Settings window height 800 → 860 to fit the new row; existing controls are bottom-anchored so none moved.
- Verified: `scripts/build-macos-app.sh` builds clean (no warnings); `codesign --verify --deep --strict` passes. Runtime-probed CoreAudio: `outputDevices()` returned AirPods Pro / BlackHole 2ch / MacBook Pro Speakers (input-only excluded), `defaultOutputDeviceUID()` read back the current AirPods default, `setDefaultOutputDevice(current)` → true, `setDefaultOutputDevice(bogus)` → false.
- Reversible by: reverting the git commit that contains this entry and the matching file changes.
- Sparkle approval: not requested.

### Microphone input selection + realtime Escape double-count fix

- Status: local only, not shipped to Sparkle. No server changes.
- Major-change count: 2 (selectable input device across both capture modes; realtime Escape now keeps its live transcript instead of forcing a re-transcribe).
- Scope: `desktop/macos/AudioCapture.swift` (new), `desktop/macos/RealtimeSession.swift`, `desktop/macos/HushlyLite.swift`, `scripts/build-macos-app.sh`.
- Change:
  - New `AudioCapture.swift`: `AudioDeviceManager` enumerates CoreAudio input devices (filters out output-only), resolves the system default's name, and points an `AVAudioEngine` input node at a chosen device UID (`kAudioOutputUnitProperty_CurrentDevice`). `PCM16` holds the shared 16 kHz mono Int16 conversion + metering. `EngineRecorder` replaces `AVAudioRecorder` for batch dictation so device selection applies to batch too — it taps the selected device and writes a 16 kHz mono Int16 WAV (uploaded to `/transcribe` as `audio/wav`; the WAV path + `.wav` retry audio already existed for realtime). The AVAudioFile is pinned to Int16/interleaved to avoid the known processing-format SIGTRAP.
  - Settings pane gains a **Microphone** popup (top of the Settings tab): "System default (<name>)" plus every input device; persisted as `Preferences.inputDeviceUID` (empty = follow system default). The list re-enumerates each time Settings refreshes; a saved device that's been unplugged falls back to System default. Applied to both realtime (`RealtimeSession.start(inputDeviceUID:)`) and batch (`EngineRecorder.start(inputDeviceUID:)`). Fixes system/virtual audio (e.g. BlackHole) seeping into transcripts while commenting on a playing video — pick the physical mic.
  - Realtime **Escape** (`cancelRealtimeForRetry`) now captures the transcript the live session already streamed and saves it to History as a "Captured (live)" entry (audio still attached), instead of saving an audio-only "Saved for retry" row. Previously Escape discarded the already-transcribed text and the History **Retry** ran Deepgram a second time on the same audio — double-counting usage for one utterance. Empty-transcript Escape still falls back to the audio-only retry entry so nothing is lost. Escape still does not paste (unchanged intent).
  - `startGlowAnimation` no longer polls `AVAudioRecorder.averagePower`; both modes push levels through their `onLevel` callback and the timer only advances the waveform phase.
  - Build script compiles the new file and links `CoreAudio`.
- Verified: `scripts/build-macos-app.sh` builds clean (no warnings); `codesign --verify --deep --strict` passes. Runtime-probed CoreAudio enumeration (found MacBook Pro Microphone, BlackHole 2ch, iPhone mic; `AudioUnitSetProperty` returned 0; input format read back 48 kHz/1ch after apply) and the `EngineRecorder` WAV write (1.2 s → valid 16 kHz WAV, no SIGTRAP).
- Reversible by: reverting the git commit that contains this entry and the matching file changes (delete `desktop/macos/AudioCapture.swift`, restore the build-script line).
- Sparkle approval: not requested.

## 2026-07-05

### Liquid Glass Tablet + Realtime Transcription

- Status: local only, not shipped to Sparkle. Server side (`/realtime` WS proxy + `/auth-check`) deploys on push to `main`.
- Major-change count: 4 (glass tablet redesign; realtime streaming mode; image opacity + non-destructive Adjust Image; on-tablet mode pill).
- Scope: `desktop/macos/HushlyLite.swift`, `desktop/macos/RealtimeSession.swift` (new), `scripts/build-macos-app.sh`, `server/http.js`, `app/auth-check+api.ts` (new), `package.json` (+`ws`).
- Change:
  - Tablet redesigned as a liquid-glass sheet: real `NSVisualEffectView` behind-window blur (masked to shape), glass tint + top sheen, rim light (user border color glows with audio level while recording), grab handle, springy pop-in and fade-out. The baked `tablet-glow.png` asset is no longer bundled.
  - New realtime transcription mode: `RealtimeSession` streams 16 kHz linear16 PCM from an `AVAudioEngine` tap to the VPS `/realtime` WebSocket proxy (Deepgram live, nova-3 multi, interim results). Words render live on the tablet (wrapped, newest-words-first suffix fitting); the rectangle sheet expands to 384×148 while streaming. Finals + trailing interim are assembled on stop, then optional GPT polish → paste → history (WAV retry audio; `/transcribe` retry now sends `audio/wav` for `.wav` files and `TranscriptStore.storeAudio` preserves extensions).
  - Mode is switchable from a pill on the tablet (LIVE / ON STOP) and a segmented control in Settings (`Preferences.transcriptionMode`, default batch — behavior unchanged unless opted in).
  - Custom tablet image now composites translucently inside the glass with an Image opacity slider (`Preferences.tabletImageOpacity`, default 0.55). The uncropped original + crop params are stored so "Adjust Image..." repositions without re-importing. Dictionary `replace` + `keyterm` params also apply to live sessions.
  - Server: `server/http.js` gains a `/realtime` WebSocket upgrade handler (auth via internal call to new `/auth-check` route; unauthorized closes 4401). Verified locally: server boots, WS upgrade + auth rejection path tested. Live Deepgram path requires the deployed VPS env. Realtime sessions do not yet record `api_usage_events` (known gap).
- Reversible by: reverting the git commit that contains this entry and the matching file changes.
- Sparkle approval: not requested.
- 2026-07-05 glass/fade pass: blur material .hudWindow → .fullScreenUI and glass tint 0.22 → 0.06 (sheet was reading opaque); Esc/stop no longer relayouts to the small pill before fading — the sheet fades from its current size with live text intact, and resets offscreen in hideTablet's completion.
- 2026-07-05 live-sheet UX pass (post-first-dictation feedback): custom image now aspect-fills instead of stretching (crop source rect matched to view aspect); live sheet starts at 96pt and rises grow-only as text wraps (animated window resize, capped at 264pt, head-trims after that); live text is left-aligned and top-anchored so words read left→right, top→down.
- 2026-07-05 crash fix: realtime mode SIGTRAP'd on the first mic buffer — `AVAudioFile(forWriting:settings:)` defaults processingFormat to deinterleaved Float32, and writing interleaved Int16 buffers trips a CoreAudio assert (`ExtAudioFile::WriteInputProc` → `CAVerboseAbort`). Fixed by pinning `commonFormat: .pcmFormatInt16, interleaved: true` at file creation. Reproduced and verified both ways with an isolated AVAudioFile write harness (old init = exit 133, new init = clean WAV).

## 2026-06-29

### Deepgram Accuracy Controls (Dictionary → Find/Replace + Keywords)

- Status: local only, not shipped to Sparkle. Server side IS deployed to Contabo (the `/transcribe` route change deploys on push to `main`).
- Major-change count: 2 (Dictionary now wired to Deepgram replace; new Keywords tab).
- Scope: `app/transcribe+api.ts` (server) and `desktop/macos/HushlyLite.swift` (macOS app).
- Change:
  - `/transcribe` now forwards whitelisted `replace` and `keyterm` query params to Deepgram (base params stay fixed and un-overridable; `keyterm` capped at 100, `replace` at 200). Backward compatible — no params = previous behavior.
  - macOS Dictionary entries now apply at the Deepgram layer via `replace=find:replace` (find lowercased per Deepgram's rule) instead of via the OpenAI `/clean` step, so they work even when GPT polish is off. Dictionary was removed from the `/clean` body to avoid double-application.
  - New "Keywords" tab (Deepgram keyterm prompting) with a multiline editor + `Preferences.keywordsText` storage; sent as `keyterm` params on transcribe.
  - `dictation=true` (spoken punctuation) was already enabled — confirmed, no change.
- Validated against the live Deepgram Nova-3 API: `replace` + `keyterm` + `dictation` + `language=multi` all return 200 and behave correctly; `+`-bearing terms (e.g. "C++") round-trip intact.
- Reversible by: reverting the git commit that contains this entry and the matching `app/transcribe+api.ts` and `desktop/macos/HushlyLite.swift` changes.
- Sparkle approval: not requested.

## 2026-05-20

### Tablet Text Styling Controls

- Status: local only, not shipped to Sparkle.
- Major-change count: 1.
- Scope: macOS settings and visible tablet renderer.
- Change: add text color, basic font, size, X offset, and Y offset controls; auto-fit long tablet text within the selected tablet shape.
- Reversible by: reverting the git commit that contains this entry and the matching `desktop/macos/HushlyLite.swift` changes.
- Sparkle approval: not requested.

### Manual-Only Sparkle Checks

- Status: local only, not shipped to Sparkle.
- Major-change count: 1.
- Scope: macOS Sparkle configuration.
- Change: disable Sparkle automatic checks and automatic update installs so users only check manually from the app menu.
- Reversible by: reverting the git commit that contains this entry and the matching `desktop/macos/Info.plist` changes.
- Sparkle approval: not requested.

### Settings Recording Preview

- Status: local only, not shipped to Sparkle.
- Major-change count: 1.
- Scope: macOS settings and visible tablet renderer.
- Change: add a recording-on tablet preview to the Settings page using the same renderer as the floating dictation tablet.
- Reversible by: reverting the git commit that contains this entry and the matching `desktop/macos/HushlyLite.swift` changes.
- Sparkle approval: not requested.

### OpenAI Cleanup Provider

- Status: local/API backend only, not shipped to Sparkle.
- Major-change count: 1.
- Scope: Hushly API cleanup and retry routes.
- Change: route transcript cleanup through `OPENAI_API_KEY` with `CLEANUP_PROVIDER=openai` and `CLEANUP_MODEL=gpt-5-nano`; `/retry` now reuses the same cleanup helper as `/clean`.
- Reversible by: reverting the git commit that contains this entry and the matching `app/clean+api.ts`, `app/retry+api.ts`, `lib/serverCleanup.ts`, and `.env.example` changes.
- Sparkle approval: not requested.

## 2026-05-26

### Deepgram Nova-3 Multilingual + Built-in Cleanup

- Status: local/API backend only, not shipped to Sparkle.
- Major-change count: 1.
- Scope: `/transcribe` and `/retry` Deepgram query parameters.
- Change: switch the Deepgram URL to `model=nova-3&language=multi&smart_format=true&punctuate=true&dictation=true`. Adds multilingual auto-detect, spoken-punctuation commands, and continues to strip "uh"/"um" via Deepgram's default `filler_words=false`.
- Reversible by: reverting the matching `app/transcribe+api.ts` and `app/retry+api.ts` changes.
- Sparkle approval: not requested.

### GPT Polish as Off-by-Default Toggle (mobile/web only)

- Status: local only, not shipped to Sparkle.
- Major-change count: 1.
- Scope: mobile/web `app/(app)/index.tsx`, `lib/api.ts`, `lib/settings.ts`. Desktop unaffected.
- Change: stop auto-calling `/clean` after every transcription. The raw Deepgram transcript is what gets copied unless the user flips the new "Polish: On" toggle in the footer. The `/clean` route is still wired and ready when the toggle is on.
- Reversible by: reverting the matching `lib/settings.ts`, `lib/api.ts`, and `app/(app)/index.tsx` changes.
- Sparkle approval: not requested.

### Usage Metrics: Words + Audio Duration + Time Saved

- Status: local/API backend + desktop, not shipped to Sparkle.
- Major-change count: 1.
- Scope: `db/migrations/0003_usage_metrics.sql`, `lib/serverAuth.ts`, `app/transcribe+api.ts`, `app/usage-summary+api.ts`, `lib/api.ts`, `app/(app)/usage.tsx`, `desktop/macos/HushlyLite.swift`.
- Change: add `word_count` and `audio_duration_seconds` to `api_usage_events`. `/transcribe` computes both (Deepgram returns `metadata.duration`). `/usage-summary` aggregates them. Mobile/web Usage screen and desktop Usage tab now show "words transcribed", "talk time", and "time saved vs typing at 100 WPM".
- Reversible by: reverting the matching files and rolling back migration 0003.
- Sparkle approval: not requested.

### Document Desktop Local-Only Storage

- Status: docs only.
- Major-change count: 0.
- Scope: `DESKTOP.md`.
- Change: clarify that the Mac app already keeps all transcripts and audio on the user's machine and never persists them to the VPS. No code change.
- Reversible by: reverting the matching `DESKTOP.md` change.
- Sparkle approval: not requested.

### Desktop GPT Polish Toggle (off by default)

- Status: local only, not shipped to Sparkle.
- Major-change count: 1.
- Scope: macOS settings + dictation flow + retry flow.
- Change: add a "Polish transcript with GPT (slower, cleaner)" checkbox to the Settings tab, defaulted off. When off, the Mac app skips the `/clean` step entirely and pastes the raw Deepgram transcript (now polished by `smart_format` + `dictation` + filler-word strip). Matches the off-by-default polish toggle that already exists on mobile/web.
- Reversible by: reverting the matching `desktop/macos/HushlyLite.swift` changes.
- Sparkle approval: not requested.

## 2026-06-02

### Session Pickup — Multi-tenant / Storage / Cleanup-Model Discussion

Captured here so the next session can resume without re-investigating. No code written yet — these are open decisions.

**Investigated and confirmed already shipping (verify these still work, do not rebuild):**
- Logical multi-tenancy via `user_id` FKs on `transcripts`, `auth_sessions`, `api_usage_events`, `app_api_keys`. Per-user audio namespacing in `lib/serverAudio.ts` (`/opt/hushly/data/audio/<userId>/`).
- Deepgram URL is `model=nova-3&language=multi&smart_format=true&punctuate=true&dictation=true` in `app/transcribe+api.ts:13` and `app/retry+api.ts:6`. Filler words intentionally stripped (default).
- Usage metrics: `word_count` + `audio_duration_seconds` columns populated by `/transcribe`, summed by `/usage-summary`, rendered in macOS Usage tab and `app/(app)/usage.tsx`. Time-saved-vs-100-WPM math runs client-side.
- Polish toggle is off-by-default on mobile/web and on the macOS Settings tab.

**Open decisions blocking next implementation step:**
1. Friend-onboarding model — current recommendation: have them self-host (fork deployment, own DB + audio dir + keys). Do **not** build per-API-key backend routing. Confirm before any infra change.
2. Upload size cap — proposed: 25 MB hard limit in `app/audio+api.ts` and `app/transcribe+api.ts` returning HTTP 413. Currently unlimited (only Node default). Confirm cap value before adding.
3. Cleanup model picker — proposed surface: add `model` field to `/clean` request body, server allow-list, persist choice in macOS `Preferences` + mobile/web settings. Open question: which models to expose? Candidates are `gpt-5-nano` (current default, cheapest), `gpt-5-mini` (bigger context, slower), and optionally a TokenRouter route to `gpt-5.5` using the same `OPENAI_API_KEY` flow as `~/.codex/auth.json`. Confirm the shortlist and which surfaces get the picker (Mac only, or Mac + mobile/web).
4. Deepgram `callback` and `tag` parameters — recommended: skip both. Audio is short dictation so synchronous transcription is faster than a callback round-trip. `tag` is only useful if multiple friends use Deepgram dashboard segmentation, which currently nobody does.

**Clarified misunderstanding (do not re-investigate):**
- `~/.codex/auth.json` is a raw `OPENAI_API_KEY` — the same key already in `.env.local`. There is no separate "Codex API". "GPT 5.4 mini" is a misremember of `gpt-5-nano` / `gpt-5-mini`. TokenRouter (`tokenrouter.tech/v1`) is what the Codex CLI uses for `gpt-5.5` and is wire-compatible with the OpenAI API, so it can be plugged in via `OPENAI_BASE_URL` if a TokenRouter option is added.

### Future / Deferred

Captured-not-built. Pulled forward only on explicit request.

- **Upload size cap (25 MB → HTTP 413)** in `/audio` and `/transcribe`. Currently uncapped at every layer. Low-risk to add.
- **Cleanup model picker** (per-request `model` field + server allow-list + UI dropdown on Mac Settings and mobile/web settings). Touches `lib/serverCleanup.ts`, `/clean`, `/retry`, `desktop/macos/HushlyLite.swift`, `lib/settings.ts`, `app/(app)/index.tsx`.
- **Cleanup-model column on `api_usage_events`** so the Usage tab can break down cost / latency per model once the picker ships.
- **Audio retention / pruning** — nothing auto-deletes old recordings today. Decide a TTL (e.g. 30 days for free tier, never for owners) and add a cron'd cleanup task only if storage growth becomes a real signal.
- **TokenRouter cleanup provider** — add `CLEANUP_PROVIDER=tokenrouter` branch in `lib/serverCleanup.ts` that hits `https://www.tokenrouter.tech/v1/chat/completions` with the same `OPENAI_API_KEY`. Only build if Jerel actually wants to A/B `gpt-5.5` against `gpt-5-nano` on real dictations.
- **Per-friend self-host packaging** — write a short `docs/self-host.md` walking a friend through forking the repo, setting their own VPS env, and pointing the mobile/desktop client at their hostname. Only build when a specific friend asks.
