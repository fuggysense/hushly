// Proxies audio bytes to Deepgram Nova-3 prerecorded endpoint.
// Client uploads raw audio as request body with Content-Type set
// (e.g. audio/m4a from iOS, audio/webm from web).

import {
  authenticateRequest,
  getSupabaseAdmin,
  jsonError,
  recordUsage,
  type RequestIdentity,
} from '@/lib/serverAuth';

const DG_URL = 'https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&punctuate=true';

export async function POST(request: Request) {
  const startedAt = Date.now();
  const admin = getSupabaseAdmin();
  let identity: RequestIdentity | null = null;
  let status = 200;
  let errorMessage = '';
  let audioBytes = 0;

  const auth = await authenticateRequest(request, admin);
  if (auth instanceof Response) return auth;
  identity = auth.identity;

  const key = process.env.DEEPGRAM_API_KEY;
  if (!key) {
    status = 500;
    errorMessage = 'DEEPGRAM_API_KEY not set on server';
    await recordUsage(auth.admin, identity, {
      route: '/transcribe',
      status,
      durationMs: Date.now() - startedAt,
      error: errorMessage,
    });
    return jsonError(status, errorMessage);
  }

  const contentType = request.headers.get('content-type') || 'audio/m4a';
  const body = await request.arrayBuffer();
  audioBytes = body.byteLength;
  if (body.byteLength === 0) {
    status = 400;
    errorMessage = 'empty body';
    await recordUsage(auth.admin, identity, {
      route: '/transcribe',
      status,
      durationMs: Date.now() - startedAt,
      audioBytes,
      error: errorMessage,
    });
    return jsonError(status, errorMessage);
  }

  const dg = await fetch(DG_URL, {
    method: 'POST',
    headers: {
      Authorization: `Token ${key}`,
      'Content-Type': contentType,
    },
    body,
  });

  if (!dg.ok) {
    const errText = await dg.text();
    status = dg.status;
    errorMessage = `deepgram: ${errText.slice(0, 400)}`;
    await recordUsage(auth.admin, identity, {
      route: '/transcribe',
      status,
      durationMs: Date.now() - startedAt,
      audioBytes,
      error: errorMessage,
    });
    return jsonError(status, errorMessage);
  }

  const dgJson = (await dg.json()) as DeepgramResponse;
  const transcript =
    dgJson?.results?.channels?.[0]?.alternatives?.[0]?.transcript?.trim() ?? '';

  await recordUsage(auth.admin, identity, {
    route: '/transcribe',
    status,
    durationMs: Date.now() - startedAt,
    audioBytes,
    outputChars: transcript.length,
  });

  return Response.json({ transcript });
}

type DeepgramResponse = {
  results?: {
    channels?: {
      alternatives?: { transcript?: string }[];
    }[];
  };
};
