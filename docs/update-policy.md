# Hushly Update Policy

Sparkle updates are opt-in release events. Do not publish a new `public/updates/appcast.xml` or update ZIP unless Jerel explicitly approves the release.

Hushly is configured for manual update checks only. Do not enable Sparkle automatic checks or automatic installs without Jerel approval.

## Release Gate

A Sparkle release needs all of the following:

1. Jerel approval in the current thread or an explicit release note.
2. More than 10 major user-facing changes accumulated since the last Sparkle release, unless Jerel overrides the threshold.
3. A clean QA pass for TypeScript, lint, macOS build, codesign verification, and local launch.
4. A pending-change log entry for every included change.
5. A git commit that makes the release reversible.

## Major Change Definition

Count a change as major when it affects a user-facing workflow, app security, billing/usage tracking, transcription behavior, auto-paste, local storage, update delivery, settings, or the visible tablet.

Do not count pure cleanup, comments, formatting, or documentation-only notes as major changes unless they change how users install, operate, or recover the app.

## Reversibility

Every change must be traceable to a git commit and a pending-change log entry. If a release causes problems, revert the release commit or ship a follow-up Sparkle release only after Jerel approves that recovery path.

## Sparkle Ship Checklist

- Increment `CFBundleShortVersionString` and `CFBundleVersion`.
- Build `dist/macos/Hushly.app`.
- Create a versioned update ZIP under `public/updates/`.
- Generate and sign `public/updates/appcast.xml`.
- Run `npx tsc --noEmit`.
- Run `npm run lint`.
- Run `scripts/build-macos-app.sh`.
- Verify `codesign --verify --deep --strict`.
- Deploy Vercel only after approval.
