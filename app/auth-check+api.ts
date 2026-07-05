// Lightweight auth probe. The VPS realtime WebSocket proxy (server/http.js)
// calls this internally to validate a bearer session or X-Hushly-API-Key
// before opening a Deepgram live connection — it keeps the key-hash and DB
// logic in lib/serverAuth.ts instead of duplicating it in plain JS.

import { authenticateRequest } from '@/lib/serverAuth';

export async function GET(request: Request) {
  const auth = await authenticateRequest(request);
  if (auth instanceof Response) return auth;
  return Response.json({ ok: true, kind: auth.identity.kind });
}
