import { createPlainAPIKey, jsonError } from '@/lib/serverAuth';
import { getDb } from '@/lib/serverDb';
import { upsertUserPassword, validateSessionToken } from '@/lib/serverUserAuth';

type AdminAction = 'list' | 'create' | 'revoke' | 'delete' | 'usage' | 'upsertUser';

type AdminBody = {
  action?: AdminAction;
  label?: string;
  tag?: string;
  user_id?: string;
  id?: string;
  days?: number;
  email?: string;
  password?: string;
  can_manage_api_keys?: boolean;
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
  const access = await authenticateAdmin(request);
  if (access instanceof Response) return access;

  let body: AdminBody = {};
  try {
    body = (await request.json()) as AdminBody;
  } catch {
    return jsonError(400, 'invalid JSON');
  }

  switch (body.action ?? 'list') {
    case 'create':
      return createKey(body, access);
    case 'revoke':
      return updateKeyStatus(body, 'revoked', access);
    case 'delete':
      return deleteKey(body, access);
    case 'usage':
      return listUsage(body, access);
    case 'upsertUser':
      return upsertUser(body, access);
    case 'list':
      return listKeys(access);
    default:
      return jsonError(400, 'unknown action');
  }
}

type AdminAccess = {
  userId: string;
  email: string;
  isOwner: boolean;
  canManageApiKeys: boolean;
};

async function authenticateAdmin(request: Request): Promise<AdminAccess | Response> {
  const authorization = request.headers.get('authorization') ?? '';
  const bearer = authorization.startsWith('Bearer ') ? authorization.slice(7).trim() : '';
  if (!bearer) return jsonError(401, 'sign-in required');

  const user = await validateSessionToken(bearer);
  if (!user) return jsonError(401, 'invalid access token');

  const { rows } = await getDb().query<{
    email: string;
    can_manage_api_keys: boolean;
  }>('select email, can_manage_api_keys from app_users where id = $1 limit 1', [user.id]);
  const current = rows[0];
  if (!current) return jsonError(401, 'invalid access token');

  const email = normalizeEmail(current.email || user.email);
  const isOwner = ownerEmails().has(email);
  return {
    userId: user.id,
    email,
    isOwner,
    canManageApiKeys: isOwner || Boolean(current.can_manage_api_keys),
  };
}

function requireApiKeyAccess(access: AdminAccess) {
  if (!access.canManageApiKeys) return jsonError(403, 'API key access not enabled for this account');
  return null;
}

function requireOwner(access: AdminAccess) {
  if (!access.isOwner) return jsonError(403, 'owner access required');
  return null;
}

async function upsertUser(body: AdminBody, access: AdminAccess) {
  const denied = requireOwner(access);
  if (denied) return denied;

  try {
    const user = await upsertUserPassword(body.email ?? '', body.password ?? '');
    const canManageApiKeys = Boolean(body.can_manage_api_keys);
    await getDb().query('update app_users set can_manage_api_keys = $2 where id = $1', [
      user.id,
      canManageApiKeys,
    ]);
    return Response.json(
      {
        user: {
          ...user,
          can_manage_api_keys: canManageApiKeys,
        },
      },
      { headers: NO_STORE }
    );
  } catch (error) {
    const status =
      error && typeof error === 'object' && 'status' in error && typeof error.status === 'number'
        ? error.status
        : 500;
    return jsonError(status, error instanceof Error ? error.message : String(error));
  }
}

async function listKeys(access: AdminAccess) {
  const denied = requireApiKeyAccess(access);
  if (denied) return denied;

  const params: unknown[] = [];
  const filter = access.isOwner ? '' : 'where user_id = $1';
  if (!access.isOwner) params.push(access.userId);

  const { rows } = await getDb().query<KeyRow>(
    `select id, label, tag, user_id, key_prefix, status, created_at, last_used_at
     from app_api_keys
     ${filter}
     order by created_at desc
     limit 500`,
    params
  );
  return Response.json({ access, keys: rows }, { headers: NO_STORE });
}

async function createKey(body: AdminBody, access: AdminAccess) {
  const denied = requireApiKeyAccess(access);
  if (denied) return denied;

  const label = body.label?.trim();
  if (!label) return jsonError(400, 'label required');
  const userId = access.isOwner ? cleanOptional(body.user_id) ?? access.userId : access.userId;

  const key = await createPlainAPIKey();
  const { rows } = await getDb().query<KeyRow>(
    `insert into app_api_keys (label, tag, user_id, key_hash, key_prefix)
     values ($1, $2, $3, $4, $5)
     returning id, label, tag, user_id, key_prefix, status, created_at, last_used_at`,
    [label, cleanOptional(body.tag), userId, key.hash, key.prefix]
  );

  return Response.json({ key: key.secret, record: rows[0] }, { headers: NO_STORE });
}

async function updateKeyStatus(body: AdminBody, status: string, access: AdminAccess) {
  const denied = requireApiKeyAccess(access);
  if (denied) return denied;
  if (!body.id) return jsonError(400, 'id required');

  const params: unknown[] = [body.id, status];
  const tenantFilter = tenantWhere(access, params);
  const { rows } = await getDb().query<KeyRow>(
    `update app_api_keys
     set status = $2
     where id = $1 ${tenantFilter}
     returning id, label, tag, user_id, key_prefix, status, created_at, last_used_at`,
    params
  );
  if (!rows[0]) return jsonError(404, 'key not found');
  return Response.json({ record: rows[0] }, { headers: NO_STORE });
}

async function deleteKey(body: AdminBody, access: AdminAccess) {
  const denied = requireApiKeyAccess(access);
  if (denied) return denied;
  if (!body.id) return jsonError(400, 'id required');

  const params: unknown[] = [body.id];
  const tenantFilter = tenantWhere(access, params);
  const { rows } = await getDb().query<KeyRow>(
    `delete from app_api_keys
     where id = $1 and status = 'revoked' ${tenantFilter}
     returning id, label, tag, user_id, key_prefix, status, created_at, last_used_at`,
    params
  );
  if (!rows[0]) return jsonError(400, 'only revoked keys can be deleted');
  return Response.json({ record: rows[0] }, { headers: NO_STORE });
}

async function listUsage(body: AdminBody, access: AdminAccess) {
  const denied = requireApiKeyAccess(access);
  if (denied) return denied;

  const days = Math.max(1, Math.min(365, body.days ?? 30));
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  const params: unknown[] = [since];
  const filters = ['created_at >= $1'];
  if (!access.isOwner) {
    params.push(access.userId);
    filters.push(`user_id = $${params.length}`);
  }
  if (body.id) {
    params.push(body.id);
    filters.push(`api_key_id = $${params.length}`);
  }

  const { rows } = await getDb().query<UsageRow>(
    `select api_key_id, api_key_label, api_key_tag, api_key_prefix, user_id, route, status,
            duration_ms, audio_bytes, input_chars, output_chars, error, created_at
     from api_usage_events
     where ${filters.join(' and ')}
     order by created_at desc
     limit 10000`,
    params
  );

  const keyParams: unknown[] = [];
  const keyFilter = access.isOwner ? '' : 'where user_id = $1';
  if (!access.isOwner) keyParams.push(access.userId);
  const { rows: keyRows } = await getDb().query<{
    id: string;
    label: string;
    tag: string | null;
    key_prefix: string;
    status: string;
  }>(`select id, label, tag, key_prefix, status from app_api_keys ${keyFilter} limit 1000`, keyParams);
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

function tenantWhere(access: AdminAccess, params: unknown[]) {
  if (access.isOwner) return '';
  params.push(access.userId);
  return `and user_id = $${params.length}`;
}

function normalizeEmail(value: string | null | undefined) {
  return (value ?? '').trim().toLowerCase();
}

function ownerEmails() {
  return new Set(
    (process.env.HUSHLY_OWNER_EMAILS ?? '')
      .split(',')
      .map((email) => normalizeEmail(email))
      .filter(Boolean)
  );
}
