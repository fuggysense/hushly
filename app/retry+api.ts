// Re-runs /transcribe + /clean for an existing transcript row.
// Looks up the audio_path, downloads from Storage with the service role,
// re-transcribes, re-cleans, and updates the row. Returns the new texts.

import { createClient } from '@supabase/supabase-js';
import { cleanupErrorMessage, cleanupErrorStatus, cleanupTranscript } from '@/lib/serverCleanup';

const DG_URL = 'https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&punctuate=true';

export async function POST(request: Request) {
  const supaUrl = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const dgKey = process.env.DEEPGRAM_API_KEY;
  if (!supaUrl || !serviceKey || !dgKey)
    return jsonError(500, 'server env not set');

  const auth = request.headers.get('authorization') ?? '';
  const accessToken = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!accessToken) return jsonError(401, 'missing access token');

  const admin = createClient(supaUrl, serviceKey, { auth: { persistSession: false } });

  const { data: userData, error: userErr } = await admin.auth.getUser(accessToken);
  if (userErr || !userData.user) return jsonError(401, 'invalid token');

  let body: { id?: string } = {};
  try {
    body = (await request.json()) as { id?: string };
  } catch {
    return jsonError(400, 'invalid JSON');
  }
  if (!body.id) return jsonError(400, 'id required');

  // Fetch the row (with user-scoped RLS via service role still checking user_id)
  const { data: row, error: rowErr } = await admin
    .from('transcripts')
    .select('id, user_id, audio_path, audio_mime')
    .eq('id', body.id)
    .single();
  if (rowErr || !row) return jsonError(404, 'transcript not found');
  if (row.user_id !== userData.user.id) return jsonError(403, 'forbidden');
  if (!row.audio_path) return jsonError(400, 'no audio stored for this transcript');

  // Download audio from Storage
  const dl = await admin.storage.from('transcript-audio').download(row.audio_path);
  if (dl.error || !dl.data) return jsonError(500, `audio download: ${dl.error?.message}`);
  const audioBuf = await dl.data.arrayBuffer();

  // Re-transcribe
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
    results?: { channels?: Array<{ alternatives?: Array<{ transcript?: string }> }> };
  };
  const raw = dgJson?.results?.channels?.[0]?.alternatives?.[0]?.transcript?.trim() ?? '';

  // Re-clean
  let cleaned = raw;
  if (raw) {
    try {
      const result = await cleanupTranscript({ text: raw });
      cleaned = result.cleaned;
    } catch (error) {
      return jsonError(cleanupErrorStatus(error), cleanupErrorMessage(error).slice(0, 400));
    }
  }

  // Update row
  const { error: upErr } = await admin
    .from('transcripts')
    .update({ raw_text: raw, cleaned_text: cleaned })
    .eq('id', body.id);
  if (upErr) return jsonError(500, upErr.message);

  return Response.json({ id: body.id, raw, cleaned });
}

function jsonError(status: number, error: string) {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
