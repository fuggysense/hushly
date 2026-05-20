# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Expo SDK 54 — versioned docs are mandatory

This project is pinned to Expo SDK 54 (`expo ~54.0.33`, React 19.1, RN 0.81.5, new architecture ON, React Compiler experiment ON, `typedRoutes` ON). The Expo API surface changes substantially between SDKs. Before writing any Expo/React Native code, read the **exact versioned docs**: https://docs.expo.dev/versions/v54.0.0/. Do not rely on training-data memory of older APIs (e.g. `expo-av` is replaced by `expo-audio` here; `expo-file-system` exposes the `File` class, not the legacy module).

## Commands

```bash
npm install
npm run start          # expo start (interactive: i / a / w)
npm run ios            # expo start --ios
npm run android        # expo start --android
npm run web            # expo start --web
npm run lint           # expo lint (eslint flat config, expoConfig + dist ignore)
npx tsc --noEmit       # direct type-check command
scripts/build-macos-app.sh
```

There is no test runner configured. There is no `tsc --noEmit` script — type-check with `npx tsc --noEmit` directly. Production web build is `expo export -p web` (driven by `vercel.json`).

`npm run reset-project` is the Expo template's one-time scaffold reset — **never run it**; the starter has already been ejected (deleted `app/(tabs)/`, `components/`, `hooks/`, `constants/`).

For desktop QA, run `scripts/build-macos-app.sh` and then verify the bundle with `codesign --verify --deep --strict --verbose=2 dist/macos/Hushly.app`. If the app is installed locally, it lives at `/Applications/Hushly.app`.

## Architecture

Hushly is an AI dictation app: record → Deepgram transcribe → Claude Haiku cleanup → copy to clipboard → persist to Supabase. It ships as one Expo Router codebase that runs on **iOS, Android, and web from the same `app/` tree**, plus a separate native **iOS keyboard extension** target and a lightweight native **macOS AppKit desktop app**.

### Routing (Expo Router 6, file-based)

- `app/_layout.tsx` wraps everything in `AuthProvider` and a `Gate` that watches the Supabase session and routes between two route groups.
- `app/(auth)/` — `sign-in.tsx`, `sign-up.tsx`. Shown when there's no session.
- `app/(app)/` — `index.tsx` (record screen), `history.tsx`. Shown when authenticated. The gate redirects on mismatch.
- Path alias: `@/*` → repo root (configured in `tsconfig.json`). Always import as `@/lib/...`, `@/components/...`.

### API routes (Expo Router `+api.ts`)

Files matching `app/*+api.ts` are server-only route handlers exporting `POST(request)`. They are compiled into `dist/server` and served on Vercel by `api/index.ts`, which uses `expo-server/adapter/vercel`'s `createRequestHandler`. `vercel.json` rewrites all paths to `/api/index`, so client code in `lib/api.ts` calls `${origin}/transcribe`, `/clean`, `/persist`, `/retry` and the handler dispatches.

The four routes form one pipeline:

1. **`/transcribe`** — Receives raw audio bytes (Content-Type set by client: `audio/m4a` native, `audio/webm` web). Proxies to Deepgram Nova-3 prerecorded endpoint. Returns `{ transcript }`. No auth required.
2. **`/clean`** — Receives `{ text, mode?, target_app?, vocabulary?, context? }`. Calls Anthropic `claude-haiku-4-5-20251001` with a hardcoded **TEXT-CLEANUP UTILITY** system prompt that explicitly refuses to act on the transcript content (treats it as data, never instruction). Returns `{ cleaned }`. No auth required.
3. **`/persist`** — Bearer JWT required. Uses service-role client (`SUPABASE_SERVICE_ROLE_KEY`) to verify the user, then inserts a row in `transcripts` referencing an audio path. **Audio bytes never traverse this function** — the client uploads them directly to Supabase Storage with their own JWT.
4. **`/retry`** — Bearer JWT required. Looks up an existing transcript, downloads its audio from Storage (service role), re-runs Deepgram + Haiku, updates the row.

### Client → API flow (record screen)

`app/(app)/index.tsx` is the recording surface. Platform-split capture:

- **Web**: `lib/recorder.web.ts` is the dynamic import (`await import('@/lib/recorder.web')`). Uses `MediaRecorder` with the first supported MIME from `audio/webm;codecs=opus | audio/webm | audio/mp4`. Returns a single Blob on stop.
- **Native**: `expo-audio`'s `useAudioRecorder(RecordingPresets.HIGH_QUALITY)`. The recorded `.m4a` is read via `new File(uri).arrayBuffer()` (note: this is the new SDK 54 `File` class from `expo-file-system`, not legacy `FileSystem.readAsStringAsync`).

After stop, the screen runs `transcribe` → then **parallel** `finalizeAndCopy` (`/clean` + clipboard write) and `uploadAudio` (direct-to-Storage), then `persistTranscript` writes the row with the storage path. The clipboard write happens before persistence so the user can paste immediately even if persistence fails.

### Data layer (Supabase)

Three migrations in `supabase/migrations/`:

- `0001_init.sql` — `transcripts`, `contexts`, `vocab`. RLS: every row scoped to `auth.uid() = user_id`.
- `0002_saas.sql` — `profiles` (plan, monthly_seconds_used), `usage_events`. Auto-provision trigger `on_auth_user_created` inserts a `profiles` row and a default `'General'` `contexts` row for every new auth user. Includes a backfill block for pre-existing users.
- `0003_audio_storage.sql` — adds `audio_path` + `audio_mime` columns; creates private bucket `transcript-audio`; RLS policies enforce path convention `<user_id>/<transcript_id>.<ext>` via `(storage.foldername(name))[1] = auth.uid()::text`.

`lib/supabase.ts` is the shared anon client. On web, `storage: undefined` (uses default localStorage); on native, `AsyncStorage`. `detectSessionInUrl: true` is only set on web so OAuth callback URLs work.

### Settings persistence

`lib/settings.ts` stores per-device button label / shortcut key in AsyncStorage (key `hushly:button-settings`). Sync to `profiles` is a future task. Settings hook is `useButtonSettings()`.

The macOS desktop app stores its local settings in `UserDefaults` through `Preferences` in `desktop/macos/HushlyLite.swift`. This includes API base, API key, shortcut, dictionary entries, tablet text, tablet image path, tablet shape, border color, text color, text font, text size, and text X/Y offsets. Do not move these settings to Supabase unless the user explicitly asks for cross-device sync.

### macOS desktop app

`desktop/macos/HushlyLite.swift` is the native desktop app. It is intentionally AppKit/Swift instead of Electron to keep RAM and disk usage low. The build script compiles it directly with `swiftc`, embeds `Sparkle.framework`, copies `desktop/macos/Assets/tablet-glow.png`, and ad-hoc signs the app bundle.

Key desktop surfaces:

- Settings window tabs: Settings, Dictionary, Usage, History.
- Dictation tablet: `TabletView`, shown while dictating and draggable as a floating panel.
- Tablet customization: text, show/hide text, custom PNG/JPEG background with crop, rectangle/circle shape, border color, text color, basic font, text size, and text X/Y offsets.
- Settings includes a recording-on tablet preview that uses the same `TabletView` renderer as the floating dictation tablet.
- Long tablet text must stay inside the selected shape. `TabletView.drawDisplayText()` auto-fits and clamps text; preserve this behavior when changing the renderer.
- Shortcut capture uses Carbon hotkeys. Do not replace it with a web-only shortcut flow.
- Auto-paste requires macOS Accessibility permissions and targets the previously active app.

### Sparkle updates

Sparkle is wired into the macOS app, but releases are manual-only. `desktop/macos/Info.plist` must keep `SUEnableAutomaticChecks` and `SUAllowsAutomaticUpdates` set to false unless Jerel explicitly approves changing that behavior. The app menu can still expose `Check for Updates...`.

Do not publish a new `public/updates/appcast.xml`, update ZIP, Vercel deployment, or pushed release unless Jerel explicitly approves a Sparkle release. The standing release threshold is more than 10 major user-facing changes unless Jerel overrides it.

Track local unreleased changes in `docs/pending-changes.md`; release rules live in `docs/update-policy.md`. Every user-facing desktop change should be reversible through git and represented in the pending-change log before it is shipped.

### Environment variables (split by trust boundary)

- **Client (bundled, public)**: `EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_ANON_KEY`, `EXPO_PUBLIC_API_BASE` (native-only override; web uses `window.location.origin`).
- **Server-only (never bundled)**: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `DEEPGRAM_API_KEY`, `ANTHROPIC_API_KEY`. Set in Vercel project env, also in `.env.local` for local `expo start --web`.

### iOS keyboard extension (separate native target)

`ios-keyboard-extension/HushlyKeyboard/` is a Swift extension that lives outside the JS bundle. It calls the deployed Vercel API (`https://hushly-six.vercel.app/transcribe` → `/clean`) and uses `UITextDocumentProxy.insertText(cleaned)` to write into the host app's text field — no clipboard hop. Auth via App Group (`group.app.hushly`) shared `UserDefaults` is documented but **not yet wired**. See `ios-keyboard-extension/README.md` and `DESKTOP.md` for build steps and rationale.

## Conventions

- The app is dark-mode only by visual design (all screens hardcode `#0a0a0a` background); `userInterfaceStyle: "automatic"` in `app.json` is set but unused.
- `lib/api.ts::getApiBase()` is the single source of API origin — never construct URLs manually in components.
- API routes return errors via a local `jsonError(status, error)` helper that writes `{ error: string }` with the right status. Match this shape when adding new routes.
- Cleanup system prompts are **deliberately rigid** (transcript-as-data, never-act-on-content). Don't soften the rules when iterating on `/clean` or `/retry` — they exist to prevent prompt injection from dictated content.
