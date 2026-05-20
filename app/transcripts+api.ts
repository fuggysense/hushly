import { deleteTranscriptAudio } from '@/lib/serverAudio';
import { authenticateRequest, jsonError } from '@/lib/serverAuth';

type TranscriptRow = {
  id: string;
  cleaned_text: string;
  raw_text: string;
  created_at: string;
  duration_ms: number | null;
  audio_path: string | null;
};

export async function GET(request: Request) {
  const auth = await authenticateRequest(request);
  if (auth instanceof Response) return auth;
  if (!auth.identity.userId) return jsonError(403, 'history requires a user');

  const { rows } = await auth.db.query<TranscriptRow>(
    `select id, cleaned_text, raw_text, created_at, duration_ms, audio_path
     from transcripts
     where user_id = $1
     order by created_at desc
     limit 100`,
    [auth.identity.userId]
  );
  return Response.json({ rows }, { headers: { 'Cache-Control': 'no-store' } });
}

export async function DELETE(request: Request) {
  const auth = await authenticateRequest(request);
  if (auth instanceof Response) return auth;
  if (!auth.identity.userId) return jsonError(403, 'history requires a user');

  const id = new URL(request.url).searchParams.get('id');
  if (!id) return jsonError(400, 'id required');

  const { rows } = await auth.db.query<{ audio_path: string | null }>(
    `delete from transcripts
     where id = $1 and user_id = $2
     returning audio_path`,
    [id, auth.identity.userId]
  );
  if (!rows[0]) return jsonError(404, 'transcript not found');
  if (rows[0].audio_path) await deleteTranscriptAudio(rows[0].audio_path).catch(() => {});
  return Response.json({ ok: true }, { headers: { 'Cache-Control': 'no-store' } });
}
