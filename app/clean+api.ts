// Server-side cleanup for raw speech transcripts.
//
// Caller may pass:
//   text:        the raw transcript (required)
//   mode:        'default' | 'email' | 'note' | 'code' (optional)
//   target_app:  hint for tone adaptation, e.g. "Slack", "Gmail", "Cursor"
//   vocabulary:  array of names/jargon to preserve verbatim
//   context:     freeform context the user maintains (e.g. project names)

import { authenticateRequest, jsonError, recordUsage } from '@/lib/serverAuth';
import {
  cleanupErrorMessage,
  cleanupErrorStatus,
  cleanupTranscript,
  type DictionaryEntry,
} from '@/lib/serverCleanup';

export async function POST(request: Request) {
  const startedAt = Date.now();
  const auth = await authenticateRequest(request);
  if (auth instanceof Response) return auth;

  let body: {
    text?: string;
    mode?: string;
    target_app?: string;
    vocabulary?: string[];
    dictionary?: DictionaryEntry[];
    context?: string;
  } = {};
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return jsonError(400, 'invalid JSON');
  }

  const raw = (body.text ?? '').trim();
  if (!raw) return Response.json({ cleaned: '' });

  try {
    const result = await cleanupTranscript({
      text: raw,
      mode: body.mode,
      targetApp: body.target_app,
      vocabulary: body.vocabulary,
      dictionary: body.dictionary,
      context: body.context,
    });

    await recordUsage(auth.db, auth.identity, {
      route: '/clean',
      status: 200,
      durationMs: Date.now() - startedAt,
      inputChars: raw.length,
      outputChars: result.cleaned.length,
      error: result.degraded ? result.warning : undefined,
    });

    return Response.json(
      {
        cleaned: result.cleaned,
        degraded: result.degraded,
        warning: result.warning,
        provider: result.provider,
        model: result.model,
      },
      result.degraded ? { headers: { 'X-Hushly-Degraded': 'cleanup-provider' } } : undefined
    );
  } catch (error) {
    const message = cleanupErrorMessage(error);
    const status = cleanupErrorStatus(error);
    await recordUsage(auth.db, auth.identity, {
      route: '/clean',
      status,
      durationMs: Date.now() - startedAt,
      inputChars: raw.length,
      error: message.slice(0, 400),
    });
    return jsonError(status, message.slice(0, 400));
  }
}
