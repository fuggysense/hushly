import {
  authenticateRequest,
  getSupabaseAdmin,
  jsonError,
  type RequestIdentity,
} from '@/lib/serverAuth';

type UsageRow = {
  route: string;
  status: number;
  duration_ms: number | null;
  audio_bytes: number | null;
  input_chars: number | null;
  output_chars: number | null;
  error: string | null;
  created_at: string;
};

export async function GET(request: Request) {
  const admin = getSupabaseAdmin();
  const auth = await authenticateRequest(request, admin);
  if (auth instanceof Response) return auth;

  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  let query = auth.admin
    .from('api_usage_events')
    .select('route, status, duration_ms, audio_bytes, input_chars, output_chars, error, created_at')
    .gte('created_at', since)
    .order('created_at', { ascending: false })
    .limit(5000);

  if (auth.identity.kind === 'api_key') {
    query = query.eq('api_key_id', auth.identity.apiKeyId);
  } else {
    query = query.eq('user_id', auth.identity.userId);
  }

  const { data, error } = await query;
  if (error) return jsonError(500, error.message);

  const rows = (data ?? []) as UsageRow[];
  const todayStart = todayStartFromRequest(request);

  return Response.json(
    {
      identity: identityPayload(auth.identity),
      today: summarize(rows.filter((row: UsageRow) => new Date(row.created_at) >= todayStart)),
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
    }
  );
}
