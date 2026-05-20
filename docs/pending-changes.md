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
