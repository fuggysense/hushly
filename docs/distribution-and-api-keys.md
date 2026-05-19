# Hushly Distribution, API Keys, and Updates

## Protecting the Vercel API

`/transcribe` and `/clean` now require one of these credentials:

- A signed-in Supabase user session sent as `Authorization: Bearer <access-token>`.
- A desktop/share key sent as `X-Hushly-API-Key: hsh_...`.

Set these Vercel environment variables before deploying the protected routes:

```sh
SUPABASE_URL=...
SUPABASE_SERVICE_ROLE_KEY=...
DEEPGRAM_API_KEY=...
ANTHROPIC_API_KEY=...
HUSHLY_MASTER_KEY=<long random owner password>
```

Apply `supabase/migrations/0004_api_keys_usage.sql` before the deployment handles real traffic.

## Creating Keys For Friends Or Users

Open the web app, sign in, go to `Admin`, and enter `HUSHLY_MASTER_KEY`.

- `Create` returns the API key once. Give that `hsh_...` value to the user.
- `Tag` is for grouping usage, for example `friend-james`, `client-a`, or `beta`.
- `List keys` shows active/revoked keys.
- `Usage` shows recent usage grouped by API key or signed-in user.

The desktop app stores the entered API key locally in macOS user defaults and sends it only to the configured Hushly API base.

## Desktop User Setup

1. Build the app with `scripts/build-macos-app.sh`.
2. Zip `dist/macos/Hushly.app`.
3. Publish the zip as a GitHub Release.
4. Tell the user to download the release zip, move `Hushly.app` to `/Applications`, open it, and paste their API key in Settings.

## Updates

Without adding Sparkle or Electron, the low-RAM update path is GitHub Releases:

1. Commit and push changes to GitHub.
2. Build a new `Hushly.app`.
3. Zip it and attach it to a new GitHub Release.
4. Users click the latest release, download the new zip, and replace the app.

For true in-app one-click auto-update later, add Sparkle to the native app and publish a signed appcast. That is a separate dependency and signing/notarization step.
