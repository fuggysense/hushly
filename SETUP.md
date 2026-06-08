# Setup — using the hosted Hushly backend

This is the fast path for contributors. You do **not** need to run a database,
Deepgram, or OpenAI yourself. You connect to the already-deployed backend at
`https://hushly.genflos.com`, which owns all the server keys and storage.

If you only want to *use* Hushly: open <https://hushly.genflos.com> in a
browser, create an account, and start dictating. Nothing to install.

The rest of this file is for working on the code.

## What you need

- Node 20+ and `npm`
- An account — you create it yourself in the app's sign-up screen. No invite or
  API key required for web/native.

You do **not** need (and should not create) `.env.local`, `.env.vps`, or any
`DATABASE_URL` / `DEEPGRAM_API_KEY` / `OPENAI_API_KEY`. Those live on the hosted
server. Adding them here only matters if you want to run your *own* backend,
which is a separate setup.

## Run it

```bash
npm install
```

### Native (recommended for local dev)

```bash
npm run ios       # or: npm run android
```

Native builds target `https://hushly.genflos.com` automatically
(`lib/apiBase.ts` → `DEFAULT_API_BASE`). Sign up in the app and the whole
pipeline — transcribe, cleanup, history — runs against the hosted backend.

### Web — read this first

`npm run web` runs an Expo dev server **and serves this repo's API routes
locally**. On web the client calls *same-origin* (`window.location.origin`,
see `lib/apiBase.ts:6`), so `npm run web` will hit your **local** `+api.ts`
handlers, not the hosted backend — and those need the server keys you don't
have. It will look broken.

For web, do one of:

- **Just use the deployed site:** <https://hushly.genflos.com> (already wired
  to the real backend). Best for trying features.
- **Develop on native** (above) if you're changing app logic.
- Only stand up a full local backend if you specifically need to work on the
  server routes — that's the self-host path, not this one.

> Web does not honor `EXPO_PUBLIC_API_BASE` today; it always uses the page
> origin. Pointing local web at the hosted backend would need a CORS change on
> the server, which isn't enabled. Don't go down that road for a UI tweak.

## Contributing

- You have **read** access to `fuggysense/hushly`. Work on **your fork** and
  open PRs against `main`. You can't push to the upstream repo, and you
  shouldn't — pushing to `main` triggers a production deploy.
- Before opening a PR: `npx tsc --noEmit` and `npm run lint` must pass (CI runs
  both and an `expo export -p web`).
- Read `CLAUDE.md` for architecture. Ignore its "push to main = deploy" and VPS
  sections for your workflow — those are the maintainer's, not yours.
