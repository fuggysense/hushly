import { readTranscriptAudio } from '@/lib/serverAudio';
import { authenticateRequest, jsonError } from '@/lib/serverAuth';
import { cleanupErrorMessage, cleanupErrorStatus, cleanupTranscript } from '@/lib/serverCleanup';

const DG_URL =
  'https://api.deepgram.com/v1/listen?model=nova-3&language=multi&smart_format=true&punctuate=true&dictation=true';

type TranscriptRow = {
  id: string;
  user_id: string;
  audio_path: string | null;
  audio_mime: string | null;
};

export async function POST(request: Request) {
  const dgKey = process.env.DEEPGRAM_API_KEY;
  if (!dgKey) return jsonError(500, 'DEEPGRAM_API_KEY not set on server');

  const auth = await authenticateRequest(request);
  if (auth instanceof Response) return auth;
  if (!auth.identity.userId) return jsonError(403, 'retry requires a user');

  let body: { id?: string } = {};
  try {
    body = (await request.json()) as { id?: string };
  } catch {
    return jsonError(400, 'invalid JSON');
  }
  if (!body.id) return jsonError(400, 'id required');

  const { rows } = await auth.db.query<TranscriptRow>(
    'select id, user_id, audio_path, audio_mime from transcripts where id = $1 limit 1',
    [body.id]
  );
  const row = rows[0];
  if (!row) return jsonError(404, 'transcript not found');
  if (row.user_id !== auth.identity.userId) return jsonError(403, 'forbidden');
  if (!row.audio_path) return jsonError(400, 'no audio stored for this transcript');

  const audioBuf = await readTranscriptAudio(row.audio_path);
  const dg = await fetch(DG_URL, {
    method: 'POST',
    headers: {
      Authorization: `Token ${dgKey}`,
      'Content-Type': row.audio_mime || 'audio/webm',
    },
    body: audioBuf,
  });
  if (!dg.ok) return jsonError(dg.status, `deepgram: ${(await dg.text()).slice(0, 200)}`);
  const dgJson = (await dg.json()) as {
    results?: { channels?: { alternatives?: { transcript?: string }[] }[] };
  };
  const raw = dgJson?.results?.channels?.[0]?.alternatives?.[0]?.transcript?.trim() ?? '';

  let cleaned = raw;
  if (raw) {
    try {
      const result = await cleanupTranscript({ text: raw });
      cleaned = result.cleaned;
    } catch (error) {
      return jsonError(cleanupErrorStatus(error), cleanupErrorMessage(error).slice(0, 400));
    }
  }

  await auth.db.query(
    'update transcripts set raw_text = $1, cleaned_text = $2, updated_at = now() where id = $3',
    [raw, cleaned, body.id]
  );

  return Response.json({ id: body.id, raw, cleaned });
}
