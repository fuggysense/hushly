import { createPlainAPIKey, jsonError } from '@/lib/serverAuth';
import { getDb } from '@/lib/serverDb';

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

  let body: AdminBody = {};
  try {
    body = (await request.json()) as AdminBody;
  } catch {
    return jsonError(400, 'invalid JSON');
  }

  const db = getDb();

  switch (body.action ?? 'list') {
    case 'create':
      return createKey(body);
    case 'revoke':
      return updateKeyStatus(body, 'revoked');
    case 'delete':
      return deleteKey(body);
    case 'usage':
      return listUsage(body);
    case 'list': {
      const { rows } = await db.query<KeyRow>(
        `select id, label, tag, user_id, key_prefix, status, created_at, last_used_at
         from app_api_keys
         order by created_at desc
         limit 500`
      );
      return Response.json({ keys: rows }, { headers: NO_STORE });
    }
    default:
      return jsonError(400, 'unknown action');
  }
}

async function createKey(body: AdminBody) {
  const label = body.label?.trim();
  if (!label) return jsonError(400, 'label required');

  const key = await createPlainAPIKey();
  const { rows } = await getDb().query<KeyRow>(
    `insert into app_api_keys (label, tag, user_id, key_hash, key_prefix)
     values ($1, $2, $3, $4, $5)
     returning id, label, tag, user_id, key_prefix, status, created_at, last_used_at`,
    [label, cleanOptional(body.tag), cleanOptional(body.user_id), key.hash, key.prefix]
  );

  return Response.json({ key: key.secret, record: rows[0] }, { headers: NO_STORE });
}

async function updateKeyStatus(body: AdminBody, status: string) {
  if (!body.id) return jsonError(400, 'id required');
  const { rows } = await getDb().query<KeyRow>(
    `update app_api_keys
     set status = $2
     where id = $1
     returning id, label, tag, user_id, key_prefix, status, created_at, last_used_at`,
    [body.id, status]
  );
  if (!rows[0]) return jsonError(404, 'key not found');
  return Response.json({ record: rows[0] }, { headers: NO_STORE });
}

async function deleteKey(body: AdminBody) {
  if (!body.id) return jsonError(400, 'id required');
  const { rows } = await getDb().query<KeyRow>(
    `delete from app_api_keys
     where id = $1 and status = 'revoked'
     returning id, label, tag, user_id, key_prefix, status, created_at, last_used_at`,
    [body.id]
  );
  if (!rows[0]) return jsonError(400, 'only revoked keys can be deleted');
  return Response.json({ record: rows[0] }, { headers: NO_STORE });
}

async function listUsage(body: AdminBody) {
  const days = Math.max(1, Math.min(365, body.days ?? 30));
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  const params: unknown[] = [since];
  let keyFilter = '';
  if (body.id) {
    params.push(body.id);
    keyFilter = 'and api_key_id = $2';
  }

  const { rows } = await getDb().query<UsageRow>(
    `select api_key_id, api_key_label, api_key_tag, api_key_prefix, user_id, route, status,
            duration_ms, audio_bytes, input_chars, output_chars, error, created_at
     from api_usage_events
     where created_at >= $1 ${keyFilter}
     order by created_at desc
     limit 10000`,
    params
  );

  const { rows: keyRows } = await getDb().query<{
    id: string;
    label: string;
    tag: string | null;
    key_prefix: string;
    status: string;
  }>('select id, label, tag, key_prefix, status from app_api_keys limit 1000');
  const keysById = new Map(keyRows.map((key) => [key.id, key]));

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
