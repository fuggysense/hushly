// Single continuous MediaRecorder. No live transcription during recording —
// caller can either stop() to get the full Blob, or cancel() to discard.

export type Recorder = {
  start: () => Promise<void>;
  stop: () => Promise<{ blob: Blob; mimeType: string }>;
  cancel: () => Promise<void>;
};

export async function createRecorder(): Promise<Recorder> {
  if (typeof navigator === 'undefined' || !navigator.mediaDevices?.getUserMedia) {
    throw new Error('Microphone not available in this browser.');
  }

  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  const mimeType = pickMime();
  const mr = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
  const chunks: BlobPart[] = [];

  mr.addEventListener('dataavailable', (e: BlobEvent) => {
    if (e.data && e.data.size > 0) chunks.push(e.data);
  });

  let cancelled = false;

  return {
    async start() {
      cancelled = false;
      chunks.length = 0;
      mr.start();
    },
    async stop() {
      return new Promise<{ blob: Blob; mimeType: string }>((resolve) => {
        if (mr.state === 'inactive') {
          stream.getTracks().forEach((t) => t.stop());
          resolve({
            blob: new Blob(chunks, { type: mr.mimeType || mimeType || 'audio/webm' }),
            mimeType: mr.mimeType || mimeType || 'audio/webm',
          });
          return;
        }
        mr.addEventListener(
          'stop',
          () => {
            stream.getTracks().forEach((t) => t.stop());
            const blob = new Blob(chunks, { type: mr.mimeType || mimeType || 'audio/webm' });
            resolve({ blob, mimeType: mr.mimeType || mimeType || 'audio/webm' });
          },
          { once: true }
        );
        mr.stop();
      });
    },
    async cancel() {
      cancelled = true;
      if (mr.state === 'recording') {
        mr.ondataavailable = null;
        try {
          mr.stop();
        } catch {
          /* */
        }
      }
      chunks.length = 0;
      stream.getTracks().forEach((t) => t.stop());
    },
  };
}

function pickMime(): string | undefined {
  if (typeof MediaRecorder === 'undefined') return undefined;
  const candidates = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4'];
  for (const m of candidates) {
    if (MediaRecorder.isTypeSupported(m)) return m;
  }
  return undefined;
}
