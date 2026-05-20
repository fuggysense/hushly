# Hushly Distribution, API Keys, and Updates

## Protecting the Hushly API

`/transcribe` and `/clean` now require one of these credentials:

- A signed-in Hushly user session sent as `Authorization: Bearer <access-token>`.
- A desktop/share key sent as `X-Hushly-API-Key: hsh_...`.

Set these VPS environment variables before deploying the protected routes:

```sh
DATABASE_URL=...
DEEPGRAM_API_KEY=...
OPENAI_API_KEY=...
CLEANUP_PROVIDER=openai
CLEANUP_MODEL=gpt-5-nano
HUSHLY_MASTER_KEY=<long random owner password>
```

Run `npm run db:migrate` before the deployment handles real traffic.

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

Sparkle update files are hosted at `https://hushly.genflos.com/updates/`.

Do not replace `public/updates/appcast.xml` or the update ZIP unless Jerel explicitly approves shipping a Sparkle update.
