// Proxies audio bytes to Deepgram Nova-3 prerecorded endpoint.
// Client uploads raw audio as request body with Content-Type set
// (e.g. audio/m4a from iOS, audio/webm from web).

const DG_URL = 'https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&punctuate=true';

export async function POST(request: Request) {
  const key = process.env.DEEPGRAM_API_KEY;
  if (!key) return jsonError(500, 'DEEPGRAM_API_KEY not set on server');

  const contentType = request.headers.get('content-type') || 'audio/m4a';
  const body = await request.arrayBuffer();
  if (body.byteLength === 0) return jsonError(400, 'empty body');

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
    return jsonError(dg.status, `deepgram: ${errText.slice(0, 400)}`);
  }

  const dgJson = (await dg.json()) as DeepgramResponse;
  const transcript =
    dgJson?.results?.channels?.[0]?.alternatives?.[0]?.transcript?.trim() ?? '';

  return Response.json({ transcript });
}

function jsonError(status: number, error: string) {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

type DeepgramResponse = {
  results?: {
    channels?: Array<{
      alternatives?: Array<{ transcript?: string }>;
    }>;
  };
};
