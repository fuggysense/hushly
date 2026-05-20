import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

const DEFAULT_AUDIO_DIR = process.env.NODE_ENV === 'production' ? '/opt/hushly/data/audio' : '.data/audio';

export function audioRoot() {
  return process.env.HUSHLY_AUDIO_DIR || DEFAULT_AUDIO_DIR;
}

export async function writeTranscriptAudio(userId: string, bytes: ArrayBuffer, mimeType: string) {
  const ext = extensionForMime(mimeType);
  const dir = path.join(audioRoot(), safeSegment(userId));
  await mkdir(dir, { recursive: true });
  const fileName = `${Date.now()}-${crypto.randomUUID()}.${ext}`;
  const absolutePath = path.join(dir, fileName);
  await writeFile(absolutePath, Buffer.from(bytes));
  return `${safeSegment(userId)}/${fileName}`;
}

export async function readTranscriptAudio(audioPath: string) {
  return readFile(resolveAudioPath(audioPath));
}

export async function deleteTranscriptAudio(audioPath: string) {
  await rm(resolveAudioPath(audioPath), { force: true });
}

function resolveAudioPath(audioPath: string) {
  const normalized = path.normalize(audioPath).replace(/^(\.\.(\/|\\|$))+/, '');
  return path.join(audioRoot(), normalized);
}

function safeSegment(value: string) {
  return value.replace(/[^a-zA-Z0-9_-]/g, '_');
}

function extensionForMime(mimeType: string) {
  if (mimeType.includes('webm')) return 'webm';
  if (mimeType.includes('mp4') || mimeType.includes('m4a')) return 'm4a';
  if (mimeType.includes('wav')) return 'wav';
  return 'audio';
}
