// Client-side helpers for talking to the API routes.
// Knows how to find the API base on both web and native.

import { Platform } from 'react-native';
import * as Clipboard from 'expo-clipboard';
import { supabase } from './supabase';

export function getApiBase(): string {
  // Web always prefers same-origin so local dev hits local API routes and
  // production hits Vercel-served routes. Native (no window) uses the
  // explicit env var (set to the Vercel URL for both Expo Go dev + prod).
  if (Platform.OS === 'web' && typeof window !== 'undefined') {
    return window.location.origin;
  }
  const explicit = process.env.EXPO_PUBLIC_API_BASE;
  if (explicit) return explicit.replace(/\/$/, '');
  return '';
}

async function fetchApi(path: string, init: RequestInit): Promise<Response> {
  const url = `${getApiBase()}${path}`;
  try {
    return await fetch(url, init);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    throw new Error(`network ${path} failed at ${url || path}: ${message}`);
  }
}

async function sessionAuthHeader(): Promise<Record<string, string>> {
  const {
    data: { session },
  } = await supabase.auth.getSession();
  return session ? { Authorization: `Bearer ${session.access_token}` } : {};
}

export async function transcribe(body: BodyInit, contentType: string): Promise<string> {
  const authHeader = await sessionAuthHeader();
  const res = await fetchApi('/transcribe', {
    method: 'POST',
    headers: { 'Content-Type': contentType, ...authHeader },
    body,
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`transcribe ${res.status}: ${t.slice(0, 200)}`);
  }
  const { transcript } = (await res.json()) as { transcript: string };
  return transcript ?? '';
}

export async function clean(
  text: string,
  options: {
    dictionary?: Array<{ trigger: string; replacement: string }>;
    vocabulary?: string[];
  } = {}
): Promise<string> {
  if (!text.trim()) return '';
  const authHeader = await sessionAuthHeader();
  const res = await fetchApi('/clean', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...authHeader },
    body: JSON.stringify({ text, ...options }),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`clean ${res.status}: ${t.slice(0, 200)}`);
  }
  const { cleaned } = (await res.json()) as { cleaned: string };
  return cleaned || text;
}

export async function getUsageSummary(): Promise<{
  identity: { kind: string; label?: string; tag?: string; email?: string };
  today: {
    requests: number;
    transcriptions: number;
    cleanups: number;
    errors: number;
    audioBytes: number;
  };
  last30d: {
    requests: number;
    transcriptions: number;
    cleanups: number;
    errors: number;
    audioBytes: number;
  };
} | null> {
  const authHeader = await sessionAuthHeader();
  if (!authHeader.Authorization) return null;
  const res = await fetchApi('/usage-summary', {
    method: 'GET',
    headers: authHeader,
  });
  if (!res.ok) return null;
  return res.json();
}

export async function persistTranscript(payload: {
  raw: string;
  cleaned: string;
  duration_ms: number;
  audio_path?: string;
  audio_mime?: string;
}): Promise<{ id: string; created_at: string; audio_path: string | null } | null> {
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return null;
  const res = await fetchApi('/persist', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${session.access_token}`,
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) return null;
  return res.json();
}

// Uploads audio bytes directly to Supabase Storage from the client (using
// the user's JWT — RLS gates the upload to their own folder).
// Returns the storage path so the persist call can reference it.
export async function uploadAudio(
  audioBytes: ArrayBuffer | Blob,
  mimeType: string
): Promise<{ path: string } | null> {
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return null;
  const ext = mimeType.includes('webm') ? 'webm' : mimeType.includes('mp4') ? 'm4a' : 'audio';
  const fileName = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
  const path = `${session.user.id}/${fileName}`;
  const body =
    audioBytes instanceof Blob ? audioBytes : new Blob([audioBytes], { type: mimeType });
  const { error } = await supabase.storage.from('transcript-audio').upload(path, body, {
    contentType: mimeType,
    upsert: false,
  });
  if (error) {
    // eslint-disable-next-line no-console
    console.warn('audio upload failed:', error.message);
    return null;
  }
  return { path };
}

export async function listTranscripts(): Promise<
  Array<{
    id: string;
    cleaned_text: string;
    raw_text: string;
    created_at: string;
    duration_ms: number | null;
    audio_path: string | null;
  }>
> {
  const { data, error } = await supabase
    .from('transcripts')
    .select('id, cleaned_text, raw_text, created_at, duration_ms, audio_path')
    .order('created_at', { ascending: false })
    .limit(100);
  if (error) return [];
  return data ?? [];
}

export async function deleteTranscript(id: string, audioPath?: string | null): Promise<boolean> {
  if (audioPath) {
    await supabase.storage.from('transcript-audio').remove([audioPath]).catch(() => {});
  }
  const { error } = await supabase.from('transcripts').delete().eq('id', id);
  return !error;
}

export async function retryTranscript(
  id: string
): Promise<{ raw: string; cleaned: string } | null> {
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return null;
  const res = await fetchApi('/retry', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${session.access_token}`,
    },
    body: JSON.stringify({ id }),
  });
  if (!res.ok) return null;
  return res.json();
}

export async function finalizeAndCopy(rawText: string, durationMs: number): Promise<{
  cleaned: string;
  cleanMs: number;
  totalMs: number;
}> {
  const t0 = Date.now();
  const cleaned = await clean(rawText);
  const cleanMs = Date.now() - t0;
  await Clipboard.setStringAsync(cleaned);
  return { cleaned, cleanMs, totalMs: Date.now() - t0 };
}
