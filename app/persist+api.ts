import { authenticateRequest, jsonError } from '@/lib/serverAuth';
import { getDb } from '@/lib/serverDb';

export async function POST(request: Request) {
  const auth = await authenticateRequest(request);
  if (auth instanceof Response) return auth;
  if (!auth.identity.userId) return jsonError(403, 'transcript persistence requires a user');

  let body: {
    raw?: string;
    cleaned?: string;
    duration_ms?: number;
    audio_path?: string;
    audio_mime?: string;
  } = {};
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return jsonError(400, 'invalid JSON');
  }

  if (!body.raw && !body.cleaned) return jsonError(400, 'raw or cleaned required');

  const { rows } = await getDb().query<{
    id: string;
    created_at: string;
    audio_path: string | null;
  }>(
    `insert into transcripts
     (user_id, raw_text, cleaned_text, duration_ms, audio_path, audio_mime)
     values ($1, $2, $3, $4, $5, $6)
     returning id, created_at, audio_path`,
    [
      auth.identity.userId,
      body.raw ?? '',
      body.cleaned ?? '',
      body.duration_ms ?? null,
      body.audio_path ?? null,
      body.audio_mime ?? null,
    ]
  );

  return Response.json(rows[0]);
}
