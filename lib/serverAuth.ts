import { createClient } from '@supabase/supabase-js';

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
      userId: string | null;
    };

type SupabaseAdmin = Omit<ReturnType<typeof createClient>, 'from'> & {
  from: (relation: string) => any;
};

type APIKeyRow = {
  id: string;
  label: string;
  tag: string | null;
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

export function getSupabaseAdmin(): SupabaseAdmin | null {
  const url = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) return null;
  return createClient(url, serviceKey, { auth: { persistSession: false } }) as unknown as SupabaseAdmin;
}

export async function authenticateRequest(
  request: Request,
  admin = getSupabaseAdmin()
): Promise<{ identity: RequestIdentity; admin: SupabaseAdmin } | Response> {
  if (!admin) return jsonError(500, 'supabase env not set');

  const authorization = request.headers.get('authorization') ?? '';
  const bearer = authorization.startsWith('Bearer ') ? authorization.slice(7).trim() : '';
  if (bearer) {
    const { data, error } = await admin.auth.getUser(bearer);
    if (error || !data.user) return jsonError(401, 'invalid access token');
    return {
      admin,
      identity: {
        kind: 'user',
        userId: data.user.id,
        email: data.user.email ?? null,
      },
    };
  }

  const apiKey = request.headers.get('x-hushly-api-key')?.trim() ?? '';
  if (!apiKey) return jsonError(401, 'missing API key');

  const keyHash = await hashSecret(apiKey);
  const { data, error } = await admin
    .from('app_api_keys')
    .select('id, label, tag, user_id, status')
    .eq('key_hash', keyHash)
    .maybeSingle();

  if (error) return jsonError(500, error.message);
  const row = data as APIKeyRow | null;
  if (!row || row.status !== 'active') return jsonError(401, 'invalid API key');

  await admin
    .from('app_api_keys')
    .update({ last_used_at: new Date().toISOString() })
    .eq('id', row.id);

  return {
    admin,
    identity: {
      kind: 'api_key',
      apiKeyId: row.id,
      label: row.label,
      tag: row.tag,
      userId: row.user_id,
    },
  };
}

export async function recordUsage(
  admin: SupabaseAdmin,
  identity: RequestIdentity | null,
  event: UsageEvent
) {
  try {
    await admin.from('api_usage_events').insert({
      api_key_id: identity?.kind === 'api_key' ? identity.apiKeyId : null,
      user_id: identity?.kind === 'user' ? identity.userId : identity?.userId ?? null,
      route: event.route,
      status: event.status,
      duration_ms: event.durationMs ?? null,
      audio_bytes: event.audioBytes ?? null,
      input_chars: event.inputChars ?? null,
      output_chars: event.outputChars ?? null,
      error: event.error ? event.error.slice(0, 500) : null,
    });
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
