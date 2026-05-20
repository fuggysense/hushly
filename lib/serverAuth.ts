import { getDb, type Db } from '@/lib/serverDb';
import { validateSessionToken } from '@/lib/serverUserAuth';

export type RequestIdentity =
  | {
      kind: 'user';
      userId: string;
      email: string | null;
    }
  | {
      kind: 'api_key';
      apiKeyId: string;
      label: string;
      tag: string | null;
      keyPrefix: string;
      userId: string | null;
    };

type APIKeyRow = {
  id: string;
  label: string;
  tag: string | null;
  key_prefix: string;
  user_id: string | null;
  status: string;
};

export type UsageEvent = {
  route: string;
  status: number;
  durationMs?: number;
  audioBytes?: number;
  inputChars?: number;
  outputChars?: number;
  error?: string;
};

export function jsonError(status: number, error: string) {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function authenticateRequest(
  request: Request,
  db = getDb()
): Promise<{ identity: RequestIdentity; db: Db } | Response> {
  const authorization = request.headers.get('authorization') ?? '';
  const bearer = authorization.startsWith('Bearer ') ? authorization.slice(7).trim() : '';
  if (bearer) {
    const user = await validateSessionToken(bearer);
    if (!user) return jsonError(401, 'invalid access token');
    return {
      db,
      identity: {
        kind: 'user',
        userId: user.id,
        email: user.email,
      },
    };
  }

  const apiKey = request.headers.get('x-hushly-api-key')?.trim() ?? '';
  if (!apiKey) return jsonError(401, 'missing API key');

  const keyHash = await hashSecret(apiKey);
  const { rows } = await db.query<APIKeyRow>(
    'select id, label, tag, key_prefix, user_id, status from app_api_keys where key_hash = $1 limit 1',
    [keyHash]
  );

  const row = rows[0];
  if (!row || row.status !== 'active') return jsonError(401, 'invalid API key');

  await db.query('update app_api_keys set last_used_at = now() where id = $1', [row.id]);

  return {
    db,
    identity: {
      kind: 'api_key',
      apiKeyId: row.id,
      label: row.label,
      tag: row.tag,
      keyPrefix: row.key_prefix,
      userId: row.user_id,
    },
  };
}

export async function recordUsage(db: Db, identity: RequestIdentity | null, event: UsageEvent) {
  try {
    await db.query(
      `insert into api_usage_events
       (api_key_id, api_key_label, api_key_tag, api_key_prefix, user_id, route, status,
        duration_ms, audio_bytes, input_chars, output_chars, error)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
      [
        identity?.kind === 'api_key' ? identity.apiKeyId : null,
        identity?.kind === 'api_key' ? identity.label : null,
        identity?.kind === 'api_key' ? identity.tag : null,
        identity?.kind === 'api_key' ? identity.keyPrefix : null,
        identity?.kind === 'user' ? identity.userId : identity?.userId ?? null,
        event.route,
        event.status,
        event.durationMs ?? null,
        event.audioBytes ?? null,
        event.inputChars ?? null,
        event.outputChars ?? null,
        event.error ? event.error.slice(0, 500) : null,
      ]
    );
  } catch {
    // Usage logging must never break transcription.
  }
}

export async function createPlainAPIKey() {
  const secret = `hsh_${randomHex(24)}`;
  return {
    secret,
    hash: await hashSecret(secret),
    prefix: `${secret.slice(0, 8)}...${secret.slice(-4)}`,
  };
}

export async function hashSecret(value: string) {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function randomHex(byteCount: number) {
  const bytes = new Uint8Array(byteCount);
  crypto.getRandomValues(bytes);
  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}
