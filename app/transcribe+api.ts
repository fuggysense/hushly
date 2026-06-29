// Proxies audio bytes to Deepgram Nova-3 prerecorded endpoint.
// Client uploads raw audio as request body with Content-Type set
// (e.g. audio/m4a from iOS, audio/webm from web).

import {
  authenticateRequest,
  jsonError,
  recordUsage,
  type RequestIdentity,
} from '@/lib/serverAuth';

// Deepgram Nova-3 multilingual + built-in cleanup features:
//  - smart_format: punctuation, capitalization, dates, numbers, URLs
//  - punctuate:    explicit punctuation (already implied by smart_format)
//  - dictation:    spoken commands ("comma","period") → "," "."
//  - language=multi: auto language detect (Nova-3 Multilingual)
// filler_words is intentionally omitted — default false strips "uh"/"um".
//
// Per-request client params (forwarded, never trusted blindly — only these
// two keys pass through):
//  - replace=FIND:REPLACE  word-level find/replace (FIND must be lowercase).
//                          Backs the desktop Dictionary tab.
//  - keyterm=TERM          boosts recognition of names/jargon (Nova-3 keyterm
//                          prompting). Backs the desktop Keywords tab.
const DG_BASE_PARAMS: Record<string, string> = {
  model: 'nova-3',
  language: 'multi',
  smart_format: 'true',
  punctuate: 'true',
  dictation: 'true',
};
const KEYTERM_MAX = 100; // Deepgram caps keyterms at 100 per request.
const REPLACE_MAX = 200;

function buildDeepgramUrl(incoming: URLSearchParams): string {
  const url = new URL('https://api.deepgram.com/v1/listen');
  for (const [k, v] of Object.entries(DG_BASE_PARAMS)) url.searchParams.set(k, v);
  for (const v of incoming.getAll('replace').slice(0, REPLACE_MAX)) {
    if (v.trim()) url.searchParams.append('replace', v);
  }
  for (const v of incoming.getAll('keyterm').slice(0, KEYTERM_MAX)) {
    if (v.trim()) url.searchParams.append('keyterm', v);
  }
  return url.toString();
}

export async function POST(request: Request) {
  const startedAt = Date.now();
  let identity: RequestIdentity | null = null;
  let status = 200;
  let errorMessage = '';
  let audioBytes = 0;

  const auth = await authenticateRequest(request);
  if (auth instanceof Response) return auth;
  identity = auth.identity;

  const key = process.env.DEEPGRAM_API_KEY;
  if (!key) {
    status = 500;
    errorMessage = 'DEEPGRAM_API_KEY not set on server';
    await recordUsage(auth.db, identity, {
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
    await recordUsage(auth.db, identity, {
      route: '/transcribe',
      status,
      durationMs: Date.now() - startedAt,
      audioBytes,
      error: errorMessage,
    });
    return jsonError(status, errorMessage);
  }

  const dgUrl = buildDeepgramUrl(new URL(request.url).searchParams);
  const dg = await fetch(dgUrl, {
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
    await recordUsage(auth.db, identity, {
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
  const audioDurationSeconds = dgJson?.metadata?.duration ?? null;
  const wordCount = transcript ? transcript.split(/\s+/).filter(Boolean).length : 0;

  await recordUsage(auth.db, identity, {
    route: '/transcribe',
    status,
    durationMs: Date.now() - startedAt,
    audioBytes,
    outputChars: transcript.length,
    wordCount,
    audioDurationSeconds: audioDurationSeconds ?? undefined,
  });

  return Response.json({ transcript });
}

type DeepgramResponse = {
  metadata?: { duration?: number };
  results?: {
    channels?: {
      alternatives?: { transcript?: string }[];
    }[];
  };
};
