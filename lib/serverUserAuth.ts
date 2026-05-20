import { createHash, pbkdf2Sync, randomBytes, timingSafeEqual } from 'node:crypto';
import { getDb } from './serverDb';

const ITERATIONS = 310_000;
const KEY_LENGTH = 32;
const DIGEST = 'sha256';
const SESSION_DAYS = 30;

export type AuthUser = {
  id: string;
  email: string;
  can_manage_api_keys?: boolean;
};

export type AuthSession = {
  access_token: string;
  expires_at: string;
  user: AuthUser;
};

type UserRow = {
  id: string;
  email: string;
  password_hash: string;
  password_salt: string;
  can_manage_api_keys: boolean;
};

export async function createUserSession(emailInput: string, password: string) {
  const email = normalizeEmail(emailInput);
  if (!email) throw statusError(400, 'email required');
  if (password.length < 8) throw statusError(400, 'password must be at least 8 characters');

  try {
    return createSession(await insertOrUpdateUserPassword(email, password, false));
  } catch (error) {
    if (isUniqueViolation(error)) throw statusError(409, 'email already exists');
    throw error;
  }
}

export async function upsertUserPassword(emailInput: string, password: string) {
  const email = normalizeEmail(emailInput);
  if (!email) throw statusError(400, 'email required');
  if (password.length < 8) throw statusError(400, 'password must be at least 8 characters');
  return insertOrUpdateUserPassword(email, password, true);
}

export async function signInUser(emailInput: string, password: string) {
  const email = normalizeEmail(emailInput);
  const db = getDb();
  const { rows } = await db.query<UserRow>(
    `select id, email, password_hash, password_salt, can_manage_api_keys
     from app_users
     where email = $1`,
    [email]
  );
  const user = rows[0];
  if (user && verifyPassword(password, user.password_salt, user.password_hash)) {
    return createSession({
      id: user.id,
      email: user.email,
      can_manage_api_keys: user.can_manage_api_keys,
    });
  }

  const legacyUser = await verifyLegacySupabasePassword(email, password);
  if (legacyUser) {
    return createSession(await insertOrUpdateUserPassword(legacyUser.email, password, true));
  }

  throw statusError(401, 'invalid email or password');
}

export async function validateSessionToken(token: string): Promise<AuthUser | null> {
  const tokenHash = hashToken(token);
  const { rows } = await getDb().query<AuthUser>(
    `select u.id, u.email, u.can_manage_api_keys
     from auth_sessions s
     join app_users u on u.id = s.user_id
     where s.token_hash = $1 and s.expires_at > now()
     limit 1`,
    [tokenHash]
  );
  return rows[0] ?? null;
}

export async function revokeSessionToken(token: string) {
  await getDb().query('delete from auth_sessions where token_hash = $1', [hashToken(token)]);
}

export function statusError(status: number, message: string) {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

function normalizeEmail(value: string) {
  return value.trim().toLowerCase();
}

function hashPassword(password: string, salt: string) {
  return pbkdf2Sync(password, salt, ITERATIONS, KEY_LENGTH, DIGEST).toString('base64');
}

async function insertOrUpdateUserPassword(email: string, password: string, upsert: boolean) {
  const salt = randomBytes(16).toString('base64');
  const passwordHash = hashPassword(password, salt);
  const conflict = upsert
    ? `on conflict (email) do update
       set password_hash = excluded.password_hash,
           password_salt = excluded.password_salt`
    : '';

  const { rows } = await getDb().query<AuthUser>(
    `insert into app_users (email, password_hash, password_salt)
     values ($1, $2, $3)
     ${conflict}
     returning id, email`,
    [email, passwordHash, salt]
  );
  return rows[0];
}

function verifyPassword(password: string, salt: string, expectedHash: string) {
  const actual = Buffer.from(hashPassword(password, salt), 'base64');
  const expected = Buffer.from(expectedHash, 'base64');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function hashToken(token: string) {
  return createHash('sha256').update(token).digest('hex');
}

async function createSession(user: AuthUser): Promise<AuthSession> {
  const token = `hsh_sess_${randomBytes(32).toString('hex')}`;
  const expiresAt = new Date(Date.now() + SESSION_DAYS * 24 * 60 * 60 * 1000).toISOString();
  await getDb().query(
    'insert into auth_sessions (user_id, token_hash, expires_at) values ($1, $2, $3)',
    [user.id, hashToken(token), expiresAt]
  );
  return {
    access_token: token,
    expires_at: expiresAt,
    user,
  };
}

function isUniqueViolation(error: unknown) {
  return Boolean(error && typeof error === 'object' && 'code' in error && error.code === '23505');
}

async function verifyLegacySupabasePassword(email: string, password: string): Promise<AuthUser | null> {
  const supabaseUrl = process.env.LEGACY_SUPABASE_URL ?? process.env.SUPABASE_URL;
  const anonKey =
    process.env.LEGACY_SUPABASE_ANON_KEY ?? process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;
  if (!supabaseUrl || !anonKey || !email || !password) return null;

  try {
    const response = await fetch(`${supabaseUrl.replace(/\/$/, '')}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: {
        apikey: anonKey,
        authorization: `Bearer ${anonKey}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ email, password }),
    });
    if (!response.ok) return null;
    const payload = (await response.json()) as {
      user?: {
        id?: string;
        email?: string;
      };
    };
    const legacyEmail = normalizeEmail(payload.user?.email ?? email);
    if (!legacyEmail) return null;
    return { id: payload.user?.id ?? legacyEmail, email: legacyEmail };
  } catch {
    return null;
  }
}
