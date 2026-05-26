import * as Clipboard from 'expo-clipboard';
import { getApiBase } from './apiBase';
import { getStoredSession } from './clientAuth';

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
  const session = await getStoredSession();
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

type UsageBucket = {
  requests: number;
  transcriptions: number;
  cleanups: number;
  errors: number;
  audioBytes: number;
  wordCount: number;
  audioDurationSeconds: number;
};

export async function getUsageSummary(): Promise<{
  identity: { kind: string; label?: string; tag?: string; email?: string };
  today: UsageBucket;
  last30d: UsageBucket;
} | null> {
  const authHeader = await sessionAuthHeader();
  if (!authHeader.Authorization) return null;
  const res = await fetchApi('/usage-summary', {
    method: 'GET',
    cache: 'no-store',
    headers: {
      ...authHeader,
      'Cache-Control': 'no-cache',
      'X-Hushly-Today-Start': localTodayStart(),
    },
  });
  if (!res.ok) return null;
  return res.json();
}

function localTodayStart() {
  const date = new Date();
  date.setHours(0, 0, 0, 0);
  return date.toISOString();
}

export async function persistTranscript(payload: {
  raw: string;
  cleaned: string;
  duration_ms: number;
  audio_path?: string;
  audio_mime?: string;
}): Promise<{ id: string; created_at: string; audio_path: string | null } | null> {
  const authHeader = await sessionAuthHeader();
  if (!authHeader.Authorization) return null;
  const res = await fetchApi('/persist', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...authHeader,
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) return null;
  return res.json();
}

export async function uploadAudio(
  audioBytes: ArrayBuffer | Blob,
  mimeType: string
): Promise<{ path: string } | null> {
  const authHeader = await sessionAuthHeader();
  if (!authHeader.Authorization) return null;
  const body =
    audioBytes instanceof Blob ? audioBytes : new Blob([audioBytes], { type: mimeType });
  const res = await fetchApi('/audio', {
    method: 'POST',
    headers: { 'Content-Type': mimeType, ...authHeader },
    body,
  });
  if (!res.ok) return null;
  return res.json();
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
  const authHeader = await sessionAuthHeader();
  if (!authHeader.Authorization) return [];
  const res = await fetchApi('/transcripts', {
    method: 'GET',
    headers: { ...authHeader, 'Cache-Control': 'no-cache' },
  });
  if (!res.ok) return [];
  const body = (await res.json()) as {
    rows?: Array<{
      id: string;
      cleaned_text: string;
      raw_text: string;
      created_at: string;
      duration_ms: number | null;
      audio_path: string | null;
    }>;
  };
  return body.rows ?? [];
}

export async function deleteTranscript(id: string): Promise<boolean> {
  const authHeader = await sessionAuthHeader();
  if (!authHeader.Authorization) return false;
  const res = await fetchApi(`/transcripts?id=${encodeURIComponent(id)}`, {
    method: 'DELETE',
    headers: authHeader,
  });
  return res.ok;
}

export async function retryTranscript(
  id: string
): Promise<{ raw: string; cleaned: string } | null> {
  const authHeader = await sessionAuthHeader();
  if (!authHeader.Authorization) return null;
  const res = await fetchApi('/retry', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...authHeader,
    },
    body: JSON.stringify({ id }),
  });
  if (!res.ok) return null;
  return res.json();
}

export async function finalizeAndCopy(
  rawText: string,
  _durationMs: number,
  options: { polish?: boolean } = {}
): Promise<{
  cleaned: string;
  cleanMs: number;
  totalMs: number;
}> {
  const t0 = Date.now();
  const cleaned = options.polish ? await clean(rawText) : rawText;
  const cleanMs = Date.now() - t0;
  await Clipboard.setStringAsync(cleaned);
  return { cleaned, cleanMs, totalMs: Date.now() - t0 };
}
