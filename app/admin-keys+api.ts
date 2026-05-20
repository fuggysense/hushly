import { createPlainAPIKey, getSupabaseAdmin, jsonError } from '@/lib/serverAuth';

type AdminAction = 'list' | 'create' | 'revoke' | 'delete' | 'usage';

type AdminBody = {
  action?: AdminAction;
  label?: string;
  tag?: string;
  user_id?: string;
  id?: string;
  days?: number;
};

type KeyRow = {
  id: string;
  label: string;
  tag: string | null;
  user_id: string | null;
  key_prefix: string;
  status: string;
  created_at: string;
  last_used_at: string | null;
};

type UsageRow = {
  api_key_id: string | null;
  api_key_label: string | null;
  api_key_tag: string | null;
  api_key_prefix: string | null;
  user_id: string | null;
  route: string;
  status: number;
  duration_ms: number | null;
  audio_bytes: number | null;
  input_chars: number | null;
  output_chars: number | null;
  error: string | null;
  created_at: string;
};

const NO_STORE = { 'Cache-Control': 'no-store' };

export async function POST(request: Request) {
  const master = process.env.HUSHLY_MASTER_KEY;
  if (!master) return jsonError(500, 'HUSHLY_MASTER_KEY not set on server');

  const provided =
    request.headers.get('x-hushly-master-key') ??
    request.headers.get('authorization')?.replace(/^Bearer\s+/i, '') ??
    '';
  if (provided !== master) return jsonError(401, 'invalid master key');

  const admin = getSupabaseAdmin();
  if (!admin) return jsonError(500, 'supabase env not set');

  let body: AdminBody = {};
  try {
    body = (await request.json()) as AdminBody;
  } catch {
    return jsonError(400, 'invalid JSON');
  }

  switch (body.action ?? 'list') {
    case 'create':
      return createKey(admin, body);
    case 'revoke':
      return revokeKey(admin, body);
    case 'delete':
      return deleteKey(admin, body);
    case 'usage':
      return listUsage(admin, body);
    case 'list':
      return listKeys(admin);
    default:
      return jsonError(400, 'unknown action');
  }
}

async function createKey(admin: NonNullable<ReturnType<typeof getSupabaseAdmin>>, body: AdminBody) {
  const label = body.label?.trim();
  if (!label) return jsonError(400, 'label required');

  const key = await createPlainAPIKey();
  const { data, error } = await admin
    .from('app_api_keys')
    .insert({
      label,
      tag: cleanOptional(body.tag),
      user_id: cleanOptional(body.user_id),
      key_hash: key.hash,
      key_prefix: key.prefix,
    })
    .select('id, label, tag, user_id, key_prefix, status, created_at, last_used_at')
    .single();

  if (error) return jsonError(500, error.message);
  return Response.json({ key: key.secret, record: data as KeyRow }, { headers: NO_STORE });
}

async function revokeKey(admin: NonNullable<ReturnType<typeof getSupabaseAdmin>>, body: AdminBody) {
  if (!body.id) return jsonError(400, 'id required');
  const { data, error } = await admin
    .from('app_api_keys')
    .update({ status: 'revoked' })
    .eq('id', body.id)
    .select('id, label, tag, user_id, key_prefix, status, created_at, last_used_at')
    .single();

  if (error) return jsonError(500, error.message);
  return Response.json({ record: data as KeyRow }, { headers: NO_STORE });
}

async function deleteKey(admin: NonNullable<ReturnType<typeof getSupabaseAdmin>>, body: AdminBody) {
  if (!body.id) return jsonError(400, 'id required');
  const { data, error } = await admin
    .from('app_api_keys')
    .delete()
    .eq('id', body.id)
    .eq('status', 'revoked')
    .select('id, label, tag, user_id, key_prefix, status, created_at, last_used_at')
    .maybeSingle();

  if (error) return jsonError(500, error.message);
  if (!data) return jsonError(400, 'only revoked keys can be deleted');
  return Response.json({ record: data as KeyRow }, { headers: NO_STORE });
}

async function listKeys(admin: NonNullable<ReturnType<typeof getSupabaseAdmin>>) {
  const { data, error } = await admin
    .from('app_api_keys')
    .select('id, label, tag, user_id, key_prefix, status, created_at, last_used_at')
    .order('created_at', { ascending: false })
    .limit(500);

  if (error) return jsonError(500, error.message);
  return Response.json({ keys: data ?? [] }, { headers: NO_STORE });
}

async function listUsage(admin: NonNullable<ReturnType<typeof getSupabaseAdmin>>, body: AdminBody) {
  const days = Math.max(1, Math.min(365, body.days ?? 30));
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  let query = admin
    .from('api_usage_events')
    .select(
      'api_key_id, api_key_label, api_key_tag, api_key_prefix, user_id, route, status, duration_ms, audio_bytes, input_chars, output_chars, error, created_at'
    )
    .gte('created_at', since)
    .order('created_at', { ascending: false })
    .limit(10000);

  if (body.id) query = query.eq('api_key_id', body.id);

  const { data, error } = await query;
  if (error) return jsonError(500, error.message);

  const rows = (data ?? []) as UsageRow[];
  const { data: keyRows } = await admin
    .from('app_api_keys')
    .select('id, label, tag, key_prefix, status')
    .limit(1000);
  const keysById = new Map(
    ((keyRows ?? []) as {
      id: string;
      label: string;
      tag: string | null;
      key_prefix: string;
      status: string;
    }[]).map((key) => [key.id, key])
  );

  return Response.json(
    {
      days,
      updatedAt: new Date().toISOString(),
      summary: summarizeByIdentity(rows).map((entry) => ({
        ...entry,
        key: entry.api_key_id
          ? keysById.get(entry.api_key_id) ?? snapshotKey(entry)
          : snapshotKey(entry),
      })),
      recent: rows.slice(0, 100),
    },
    { headers: NO_STORE }
  );
}

function snapshotKey(entry: {
  api_key_label: string | null;
  api_key_tag: string | null;
  api_key_prefix: string | null;
}) {
  if (!entry.api_key_label && !entry.api_key_prefix) return null;
  return {
    label: entry.api_key_label ?? 'Deleted API key',
    tag: entry.api_key_tag,
    key_prefix: entry.api_key_prefix ?? 'deleted',
    status: 'deleted',
  };
}

function summarizeByIdentity(rows: UsageRow[]) {
  const summary = new Map<
    string,
    {
      api_key_id: string | null;
      api_key_label: string | null;
      api_key_tag: string | null;
      api_key_prefix: string | null;
      user_id: string | null;
      requests: number;
      transcriptions: number;
      cleanups: number;
      errors: number;
      audio_bytes: number;
      input_chars: number;
      output_chars: number;
    }
  >();

  for (const row of rows) {
    const key = row.api_key_id ?? row.api_key_prefix ?? `user:${row.user_id ?? 'unknown'}`;
    const existing =
      summary.get(key) ??
      {
        api_key_id: row.api_key_id,
        api_key_label: row.api_key_label,
        api_key_tag: row.api_key_tag,
        api_key_prefix: row.api_key_prefix,
        user_id: row.user_id,
        requests: 0,
        transcriptions: 0,
        cleanups: 0,
        errors: 0,
        audio_bytes: 0,
        input_chars: 0,
        output_chars: 0,
      };

    existing.requests += 1;
    if (row.route === '/transcribe') existing.transcriptions += 1;
    if (row.route === '/clean') existing.cleanups += 1;
    if (row.status >= 400 || row.error) existing.errors += 1;
    existing.audio_bytes += row.audio_bytes ?? 0;
    existing.input_chars += row.input_chars ?? 0;
    existing.output_chars += row.output_chars ?? 0;
    summary.set(key, existing);
  }

  return Array.from(summary.values());
}

function cleanOptional(value: string | undefined) {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}
