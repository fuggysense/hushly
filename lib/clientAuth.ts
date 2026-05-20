import AsyncStorage from '@react-native-async-storage/async-storage';
import { Platform } from 'react-native';
import { getApiBase } from './apiBase';

const SESSION_KEY = 'hushly:session';

export type HushlySession = {
  access_token: string;
  expires_at: string;
  user: {
    id: string;
    email: string;
  };
};

type Listener = (session: HushlySession | null) => void;

const listeners = new Set<Listener>();

export async function getStoredSession(): Promise<HushlySession | null> {
  const raw = await getStorageItem(SESSION_KEY);
  if (!raw) return null;
  try {
    const session = JSON.parse(raw) as HushlySession;
    if (!session.access_token || new Date(session.expires_at).getTime() <= Date.now()) {
      await setStoredSession(null);
      return null;
    }
    return session;
  } catch {
    await setStoredSession(null);
    return null;
  }
}

export async function setStoredSession(session: HushlySession | null) {
  if (session) {
    await setStorageItem(SESSION_KEY, JSON.stringify(session));
  } else {
    await removeStorageItem(SESSION_KEY);
  }
  for (const listener of listeners) listener(session);
}

export function onSessionChange(listener: Listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export async function signInWithPassword(email: string, password: string) {
  return authRequest('signIn', email, password);
}

export async function signUp(email: string, password: string) {
  return authRequest('signUp', email, password);
}

export async function signOut() {
  const session = await getStoredSession();
  if (session) {
    await fetch(`${getApiBase()}/auth`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({ action: 'signOut' }),
    }).catch(() => {});
  }
  await setStoredSession(null);
}

async function authRequest(action: 'signIn' | 'signUp', email: string, password: string) {
  const res = await fetch(`${getApiBase()}/auth`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, email, password }),
  });
  const body = (await res.json().catch(() => ({}))) as {
    session?: HushlySession;
    error?: string;
  };
  if (!res.ok || !body.session) {
    return { error: { message: body.error ?? `${action} failed` }, data: { session: null } };
  }
  await setStoredSession(body.session);
  return { error: null, data: { session: body.session } };
}

async function getStorageItem(key: string) {
  if (Platform.OS === 'web' && typeof window !== 'undefined') {
    return window.localStorage.getItem(key);
  }
  return AsyncStorage.getItem(key);
}

async function setStorageItem(key: string, value: string) {
  if (Platform.OS === 'web' && typeof window !== 'undefined') {
    window.localStorage.setItem(key, value);
    return;
  }
  await AsyncStorage.setItem(key, value);
}

async function removeStorageItem(key: string) {
  if (Platform.OS === 'web' && typeof window !== 'undefined') {
    window.localStorage.removeItem(key);
    return;
  }
  await AsyncStorage.removeItem(key);
}
