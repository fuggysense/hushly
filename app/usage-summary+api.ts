import { authenticateRequest, type RequestIdentity } from '@/lib/serverAuth';

type UsageRow = {
  route: string;
  status: number;
  duration_ms: number | null;
  audio_bytes: number | null;
  input_chars: number | null;
  output_chars: number | null;
  error: string | null;
  created_at: string;
  word_count: number | null;
  audio_duration_seconds: number | string | null;
};

export async function GET(request: Request) {
  const auth = await authenticateRequest(request);
  if (auth instanceof Response) return auth;

  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const identityFilter =
    auth.identity.kind === 'api_key' ? 'api_key_id = $2' : 'user_id = $2';
  const identityValue =
    auth.identity.kind === 'api_key' ? auth.identity.apiKeyId : auth.identity.userId;

  const { rows } = await auth.db.query<UsageRow>(
    `select route, status, duration_ms, audio_bytes, input_chars, output_chars, error,
            created_at, word_count, audio_duration_seconds
     from api_usage_events
     where created_at >= $1 and ${identityFilter}
     order by created_at desc
     limit 5000`,
    [since, identityValue]
  );
  const todayStart = todayStartFromRequest(request);

  return Response.json(
    {
      identity: identityPayload(auth.identity),
      today: summarize(rows.filter((row) => new Date(row.created_at) >= todayStart)),
      last30d: summarize(rows),
      recent: rows.slice(0, 20),
      updatedAt: new Date().toISOString(),
    },
    { headers: { 'Cache-Control': 'no-store' } }
  );
}

function identityPayload(identity: RequestIdentity) {
  if (identity.kind === 'api_key') {
    return {
      kind: identity.kind,
      label: identity.label,
      tag: identity.tag,
      keyPrefix: identity.keyPrefix,
    };
  }
  return {
    kind: identity.kind,
    email: identity.email,
  };
}

function todayStartFromRequest(request: Request) {
  const header = request.headers.get('x-hushly-today-start');
  if (header) {
    const date = new Date(header);
    if (!Number.isNaN(date.getTime())) return date;
  }

  const fallback = new Date();
  fallback.setHours(0, 0, 0, 0);
  return fallback;
}

function summarize(rows: UsageRow[]) {
  return rows.reduce(
    (acc, row) => {
      acc.requests += 1;
      if (row.route === '/transcribe') acc.transcriptions += 1;
      if (row.route === '/clean') acc.cleanups += 1;
      if (row.status >= 400 || row.error) acc.errors += 1;
      acc.audioBytes += row.audio_bytes ?? 0;
      acc.durationMs += row.duration_ms ?? 0;
      acc.inputChars += row.input_chars ?? 0;
      acc.outputChars += row.output_chars ?? 0;
      acc.wordCount += row.word_count ?? 0;
      // pg returns NUMERIC as a string to preserve precision; coerce.
      const audioSeconds =
        typeof row.audio_duration_seconds === 'string'
          ? Number(row.audio_duration_seconds)
          : row.audio_duration_seconds ?? 0;
      acc.audioDurationSeconds += Number.isFinite(audioSeconds) ? audioSeconds : 0;
      return acc;
    },
    {
      requests: 0,
      transcriptions: 0,
      cleanups: 0,
      errors: 0,
      audioBytes: 0,
      durationMs: 0,
      inputChars: 0,
      outputChars: 0,
      wordCount: 0,
      audioDurationSeconds: 0,
    }
  );
}
