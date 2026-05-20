# Expo HAS CHANGED

Read the exact versioned docs at https://docs.expo.dev/versions/v54.0.0/ before writing any code.

# Hushly Desktop + Release Rules

Read `CLAUDE.md` before editing. The repo contains both the Expo app and a native AppKit macOS app at `desktop/macos/HushlyLite.swift`.

The macOS app is not Electron. Keep it lightweight, native, and dependency-free unless Jerel explicitly approves a new dependency.

For desktop work:

- Build with `scripts/build-macos-app.sh`.
- Type-check with `npx tsc --noEmit`.
- Lint with `npm run lint`.
- Verify the macOS bundle with `codesign --verify --deep --strict --verbose=2 dist/macos/Hushly.app`.
- Install locally only by copying `dist/macos/Hushly.app` to `/Applications/Hushly.app`.

Tablet behavior is user-facing. Preserve the draggable floating tablet, rectangle/circle shape options, custom cropped background image, border color, show/hide text toggle, and the text styling controls: color, font, size, X offset, and Y offset. Long text must auto-fit inside the tablet instead of overflowing.

Sparkle updates are manual release events. Do not change `public/updates/appcast.xml`, create a new update ZIP, deploy Vercel, push a release, or enable automatic Sparkle checks/installs unless Jerel explicitly approves it. Current policy: ship to Sparkle only after approval and when more than 10 major user-facing changes have accumulated, unless Jerel overrides the threshold.

Track unreleased user-facing changes in `docs/pending-changes.md`. Release rules are in `docs/update-policy.md`.
