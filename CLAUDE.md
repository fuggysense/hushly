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
npm run db:migrate     # apply plain Postgres migrations
npm run serve:vps      # run the exported VPS HTTP server after expo export
npx tsc --noEmit       # direct type-check command
scripts/build-macos-app.sh
```

There is no test runner configured. There is no `tsc --noEmit` script — type-check with `npx tsc --noEmit` directly. Production web build is `expo export -p web`; Vercel can still serve the rollback path through `vercel.json`, while the VPS serves the same export through `server/http.js`.

`npm run reset-project` is the Expo template's one-time scaffold reset — **never run it**; the starter has already been ejected (deleted `app/(tabs)/`, `components/`, `hooks/`, `constants/`).

For desktop QA, run `scripts/build-macos-app.sh` and then verify the bundle with `codesign --verify --deep --strict --verbose=2 dist/macos/Hushly.app`. If the app is installed locally, it lives at `/Applications/Hushly.app`.

## Architecture

Hushly is an AI dictation app: record → Deepgram transcribe → OpenAI cleanup → copy to clipboard → persist to Hushly Postgres. It ships as one Expo Router codebase that runs on **iOS, Android, and web from the same `app/` tree**, plus a separate native **iOS keyboard extension** target and a lightweight native **macOS AppKit desktop app**.

### Routing (Expo Router 6, file-based)

- `app/_layout.tsx` wraps everything in `AuthProvider` and a `Gate` that watches the Hushly session and routes between two route groups.
- `app/(auth)/` — `sign-in.tsx`, `sign-up.tsx`. Shown when there's no session.
- `app/(app)/` — `index.tsx` (record screen), `history.tsx`. Shown when authenticated. The gate redirects on mismatch.
- Path alias: `@/*` → repo root (configured in `tsconfig.json`). Always import as `@/lib/...`, `@/components/...`.

### API routes (Expo Router `+api.ts`)

Files matching `app/*+api.ts` are server-only route handlers exporting HTTP methods. They are compiled into `dist/server` and served either by Vercel rollback (`api/index.ts` using `expo-server/adapter/vercel`) or the Contabo VPS (`server/http.js` using `expo-server/adapter/http`). Client code in `lib/api.ts` calls same-origin on web and `EXPO_PUBLIC_API_BASE` / `https://hushly.genflos.com` on native.

The main routes form one pipeline:

1. **`/auth`** — Creates Hushly users/sessions in Postgres. Client stores the bearer session locally.
2. **`/transcribe`** — Requires a bearer session or `X-Hushly-API-Key`. Receives raw audio bytes (Content-Type set by client: `audio/m4a` native, `audio/webm` web). Proxies to Deepgram Nova-3 prerecorded endpoint. Returns `{ transcript }`.
3. **`/clean`** — Requires a bearer session or `X-Hushly-API-Key`. Receives `{ text, mode?, target_app?, vocabulary?, context? }`. Calls the server cleanup helper in `lib/serverCleanup.ts`, currently defaulting to OpenAI `gpt-5-nano` via `OPENAI_API_KEY`, `CLEANUP_PROVIDER=openai`, and `CLEANUP_MODEL=gpt-5-nano`. The cleanup prompt explicitly refuses to act on the transcript content (treats it as data, never instruction). Returns `{ cleaned }`.
4. **`/audio`** — Bearer session required. Stores retry audio on the VPS filesystem under `HUSHLY_AUDIO_DIR`.
5. **`/persist`** — Bearer session required. Inserts the transcript row in Postgres referencing an audio path.
6. **`/retry`** — Bearer session required. Looks up an existing transcript, reads its stored audio, re-runs Deepgram + OpenAI cleanup, updates the row.
7. **`/realtime`** — WebSocket (VPS only, handled in `server/http.js`, not an Expo route). Auth via `X-Hushly-API-Key` or bearer header, validated against **`/auth-check`**. Client streams 16 kHz linear16 PCM; server proxies to Deepgram live and relays `{ type: 'interim' | 'final', text }` events. Backs the desktop app's realtime mode. Not served on the Vercel rollback path.

### Client → API flow (record screen)

`app/(app)/index.tsx` is the recording surface. Platform-split capture:

- **Web**: `lib/recorder.web.ts` is the dynamic import (`await import('@/lib/recorder.web')`). Uses `MediaRecorder` with the first supported MIME from `audio/webm;codecs=opus | audio/webm | audio/mp4`. Returns a single Blob on stop.
- **Native**: `expo-audio`'s `useAudioRecorder(RecordingPresets.HIGH_QUALITY)`. The recorded `.m4a` is read via `new File(uri).arrayBuffer()` (note: this is the new SDK 54 `File` class from `expo-file-system`, not legacy `FileSystem.readAsStringAsync`).

After stop, the screen runs `transcribe` → then **parallel** `finalizeAndCopy` (`/clean` + clipboard write) and `uploadAudio` (`/audio`), then `persistTranscript` writes the row with the audio path. The clipboard write happens before persistence so the user can paste immediately even if persistence fails.

### Data layer (Postgres on VPS)

Plain Postgres migrations live in `db/migrations/` and are applied by `npm run db:migrate`. `lib/serverDb.ts` owns the connection pool. `lib/serverAuth.ts` authenticates bearer sessions and API keys, and records usage events. User auth is local to Hushly in `app_users` + `auth_sessions`; API keys, usage, transcripts, and retry audio references all live in the same Postgres database.

### Settings persistence

`lib/settings.ts` stores per-device button label / shortcut key in AsyncStorage (key `hushly:button-settings`). Sync to `profiles` is a future task. Settings hook is `useButtonSettings()`.

The macOS desktop app stores its local settings in `UserDefaults` through `Preferences` in `desktop/macos/HushlyLite.swift`. This includes API base, API key, shortcut, dictionary entries, transcription mode (batch vs realtime), tablet text, tablet image path (plus original image path, crop zoom/offsets, and image opacity), tablet shape, border color, text color, text font, text size, and text X/Y offsets. Do not move these settings to Postgres unless the user explicitly asks for cross-device sync.

### macOS desktop app

`desktop/macos/HushlyLite.swift` (plus `desktop/macos/RealtimeSession.swift` for live streaming) is the native desktop app. It is intentionally AppKit/Swift instead of Electron to keep RAM and disk usage low. The build script compiles both files directly with `swiftc`, embeds `Sparkle.framework`, and ad-hoc signs the app bundle.

Key desktop surfaces:

- Settings window tabs: Settings, Dictionary, Usage, History.
- Dictation tablet: `TabletView`, shown while dictating and draggable as a floating panel.
- Tablet customization: text, show/hide text, custom PNG/JPEG background with crop (non-destructive — original + crop params are stored so "Adjust Image..." can reposition), image opacity inside the glass, rectangle/circle shape, border color, text color, basic font, text size, and text X/Y offsets.
- The tablet is a liquid-glass sheet: `NSVisualEffectView` behind-window blur masked to the shape, with the user's image composited translucently above it. A pill on the sheet toggles between live transcription and transcribe-on-stop; live mode expands the rectangle sheet to fit streaming text.
- Settings includes a recording-on tablet preview that uses the same `TabletView` renderer as the floating dictation tablet.
- Long tablet text must stay inside the selected shape. `TabletView.drawDisplayText()` auto-fits and clamps text; preserve this behavior when changing the renderer.
- Shortcut capture uses Carbon hotkeys. Do not replace it with a web-only shortcut flow.
- Auto-paste requires macOS Accessibility permissions and targets the previously active app.

### Sparkle updates

Sparkle is wired into the macOS app, but releases are manual-only. `desktop/macos/Info.plist` must keep `SUEnableAutomaticChecks` and `SUAllowsAutomaticUpdates` set to false unless Jerel explicitly approves changing that behavior. The app menu can still expose `Check for Updates...`.

Do not publish a new `public/updates/appcast.xml`, update ZIP, or pushed Sparkle release unless Jerel explicitly approves a Sparkle release. The standing release threshold is more than 10 major user-facing changes unless Jerel overrides it.

Track local unreleased changes in `docs/pending-changes.md`; release rules live in `docs/update-policy.md`. Every user-facing desktop change should be reversible through git and represented in the pending-change log before it is shipped.

### Environment variables (split by trust boundary)

- **Client (bundled, public)**: `EXPO_PUBLIC_API_BASE` (native override; web uses `window.location.origin`).
- **Server-only (never bundled)**: `DATABASE_URL`, `DATABASE_SSL`, `DEEPGRAM_API_KEY`, `OPENAI_API_KEY`, `CLEANUP_PROVIDER`, `CLEANUP_MODEL`, `HUSHLY_MASTER_KEY`. Set in `.env.vps` on Contabo and `.env.local` for local server testing.

### iOS keyboard extension (separate native target)

`ios-keyboard-extension/HushlyKeyboard/` is a Swift extension that lives outside the JS bundle. It calls the deployed VPS API (`https://hushly.genflos.com/transcribe` → `/clean`) and uses `UITextDocumentProxy.insertText(cleaned)` to write into the host app's text field — no clipboard hop. Auth via App Group (`group.app.hushly`) shared `UserDefaults` is documented but **not yet wired**. See `ios-keyboard-extension/README.md` and `DESKTOP.md` for build steps and rationale.

## Conventions

- The app is dark-mode only by visual design (all screens hardcode `#0a0a0a` background); `userInterfaceStyle: "automatic"` in `app.json` is set but unused.
- `lib/apiBase.ts::getApiBase()` is the single source of API origin — never construct URLs manually in components.
- API routes return errors via a local `jsonError(status, error)` helper that writes `{ error: string }` with the right status. Match this shape when adding new routes.
- Cleanup system prompts are **deliberately rigid** (transcript-as-data, never-act-on-content). Don't soften the rules when iterating on `lib/serverCleanup.ts`, `/clean`, or `/retry` — they exist to prevent prompt injection from dictated content.

## Onboarding a new user (signup → first dictation)

The app is multi-tenant at the row level (every table FK's to `app_users.id`), but single-tenant at the infrastructure level — one shared Postgres, one shared `/opt/hushly/data/audio` directory on the Contabo VPS. There is no per-user database or per-user storage seam.

**Standard flow (web/native):**
1. User opens the app → unauthenticated → `app/(auth)/sign-up.tsx` shown by the Gate in `app/_layout.tsx`.
2. Client POSTs `/auth` → `lib/serverAuth.ts` hashes the password, inserts into `app_users`, creates a session row in `auth_sessions`, returns a bearer token.
3. Token is stored locally (AsyncStorage on native, localStorage on web). All subsequent `/transcribe`, `/clean`, `/audio`, `/persist` calls send `Authorization: Bearer <token>`.
4. First recording on the record screen runs the standard pipeline. The user appears in `api_usage_events` from the first `/transcribe` call.

**Owner accounts** (`HUSHLY_OWNER_EMAILS`) get `can_manage_api_keys=true` automatically and can mint admin API keys via `/admin-api-keys` for the iOS keyboard, the macOS app, or external tools.

**Letting a friend use Hushly today:** the recommended path is to give them an account on the shared VPS (they sign up, their rows isolate via `user_id`). Audio + transcripts go in the shared dir / DB but are queryable only by them. **Self-hosting** is the only way to keep their audio off Jerel's VPS — fork the deployment: spin up their own Contabo box (or any VPS), point it at their own `DATABASE_URL`, their own `HUSHLY_AUDIO_DIR`, their own Deepgram + OpenAI keys, and have them set `EXPO_PUBLIC_API_BASE` to their hostname. There is **no per-API-key backend routing**; do not build it for one friend.

## Pushing changes to GitHub (and auto-deploy)

Remote: `github.com/fuggysense/hushly` → `main` branch.

**Push to `main` = production deploy.** The `.github/workflows/deploy-contabo.yml` action runs on every push to `main`:
1. `verify` job — `npm ci`, `npx tsc --noEmit`, `npm run lint`, `npx expo export -p web`. If any fails, deploy is blocked.
2. `deploy` job — SSHes to Contabo, rsyncs the repo to `/opt/hushly/app/`, writes `/opt/hushly/.env` from the `HUSHLY_VPS_ENV` GitHub secret, runs `docker build --no-cache`, applies pending Postgres migrations, restarts the `app` container, then brings up `caddy` + `backup`.

Required GitHub secrets (already configured): `CONTABO_HOST`, `CONTABO_USER`, `CONTABO_SSH_KEY`, `HUSHLY_VPS_ENV` (full `.env` contents — update this secret in Settings → Secrets when adding new server-only vars like `CLEANUP_MODEL_<NAME>`).

**Before pushing — local gate:**

```bash
npx tsc --noEmit
npm run lint
npm run db:migrate          # only if you added a migration; runs against local Postgres
git status
git add -p                  # review hunks one by one
git commit -m "<imperative message>"
git push origin main
```

After push, watch the deploy:

```bash
gh run watch                                       # follow the GitHub Action
ssh root@194.238.27.4 'docker compose -f /opt/hushly/app/docker-compose.vps.yml logs -f app'
```

**Never push** if `tsc --noEmit` has errors — the verify job will fail and the VPS will keep running the previous image, but the failed run wastes a build slot and clouds the deploy history.

**Desktop releases are separate.** Pushing to `main` does not ship a new macOS build. Sparkle releases follow `docs/update-policy.md` (manual only, >10 user-facing changes threshold, Jerel-approved). The `docs/pending-changes.md` log is the changelog of record for desktop.

## Cleanup / future-changelog policy

When a discussion produces ideas that aren't being built today, **do not start them**. Capture them as a dated entry in `docs/pending-changes.md` under a `### Future / Deferred` heading so they survive context loss. Pickup state from open conversations also belongs there — the file is the resume point after a `/clear`, `/compact`, or session timeout.
