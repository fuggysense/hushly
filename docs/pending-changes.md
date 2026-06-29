# Pending Changes

This file tracks local changes that have not been shipped through Sparkle.

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
