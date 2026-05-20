import { jsonError } from '@/lib/serverAuth';
import { createUserSession, revokeSessionToken, signInUser } from '@/lib/serverUserAuth';

type AuthBody = {
  action?: 'signIn' | 'signUp' | 'signOut';
  email?: string;
  password?: string;
};

export async function POST(request: Request) {
  let body: AuthBody = {};
  try {
    body = (await request.json()) as AuthBody;
  } catch {
    return jsonError(400, 'invalid JSON');
  }

  try {
    switch (body.action) {
      case 'signUp':
        return Response.json(
          { session: await createUserSession(body.email ?? '', body.password ?? '') },
          { headers: { 'Cache-Control': 'no-store' } }
        );
      case 'signIn':
        return Response.json(
          { session: await signInUser(body.email ?? '', body.password ?? '') },
          { headers: { 'Cache-Control': 'no-store' } }
        );
      case 'signOut': {
        const authorization = request.headers.get('authorization') ?? '';
        const token = authorization.startsWith('Bearer ') ? authorization.slice(7).trim() : '';
        if (token) await revokeSessionToken(token);
        return Response.json({ ok: true }, { headers: { 'Cache-Control': 'no-store' } });
      }
      default:
        return jsonError(400, 'unknown auth action');
    }
  } catch (error) {
    const status = statusFromError(error);
    return jsonError(status, error instanceof Error ? error.message : String(error));
  }
}

function statusFromError(error: unknown) {
  if (error && typeof error === 'object' && 'status' in error && typeof error.status === 'number') {
    return error.status;
  }
  return 500;
}
