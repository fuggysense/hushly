// Persists a transcript row + optional audio metadata.
// Audio bytes are uploaded directly by the client to Supabase Storage
// (with their JWT) so the file doesn't traverse our serverless function.
// This route only writes the row referencing the storage path.

import { createClient } from '@supabase/supabase-js';

export async function POST(request: Request) {
  const url = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) return jsonError(500, 'supabase env not set');

  const auth = request.headers.get('authorization') ?? '';
  const accessToken = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!accessToken) return jsonError(401, 'missing access token');

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  const { data: userData, error: userErr } = await admin.auth.getUser(accessToken);
  if (userErr || !userData.user) return jsonError(401, 'invalid token');

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

  const { data, error } = await admin
    .from('transcripts')
    .insert({
      user_id: userData.user.id,
      raw_text: body.raw ?? '',
      cleaned_text: body.cleaned ?? '',
      duration_ms: body.duration_ms ?? null,
      audio_path: body.audio_path ?? null,
      audio_mime: body.audio_mime ?? null,
    })
    .select('id, created_at, audio_path')
    .single();

  if (error) return jsonError(500, error.message);
  return Response.json({ id: data.id, created_at: data.created_at, audio_path: data.audio_path });
}

function jsonError(status: number, error: string) {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
