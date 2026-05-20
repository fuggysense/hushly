import { createHash, pbkdf2Sync, randomBytes, timingSafeEqual } from 'node:crypto';
import { getDb } from './serverDb';

const ITERATIONS = 310_000;
const KEY_LENGTH = 32;
const DIGEST = 'sha256';
const SESSION_DAYS = 30;

export type AuthUser = {
  id: string;
  email: string;
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
};

export async function createUserSession(emailInput: string, password: string) {
  const email = normalizeEmail(emailInput);
  if (!email) throw statusError(400, 'email required');
  if (password.length < 8) throw statusError(400, 'password must be at least 8 characters');

  const salt = randomBytes(16).toString('base64');
  const passwordHash = hashPassword(password, salt);

  try {
    const { rows } = await getDb().query<AuthUser>(
      `insert into app_users (email, password_hash, password_salt)
       values ($1, $2, $3)
       returning id, email`,
      [email, passwordHash, salt]
    );
    return createSession(rows[0]);
  } catch (error) {
    if (isUniqueViolation(error)) throw statusError(409, 'email already exists');
    throw error;
  }
}

export async function signInUser(emailInput: string, password: string) {
  const email = normalizeEmail(emailInput);
  const { rows } = await getDb().query<UserRow>(
    'select id, email, password_hash, password_salt from app_users where email = $1',
    [email]
  );
  const user = rows[0];
  if (!user || !verifyPassword(password, user.password_salt, user.password_hash)) {
    throw statusError(401, 'invalid email or password');
  }
  return createSession({ id: user.id, email: user.email });
}

export async function validateSessionToken(token: string): Promise<AuthUser | null> {
  const tokenHash = hashToken(token);
  const { rows } = await getDb().query<AuthUser>(
    `select u.id, u.email
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
