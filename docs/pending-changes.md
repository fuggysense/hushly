# Pending Changes

This file tracks local changes that have not been shipped through Sparkle.

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
