import { writeTranscriptAudio } from '@/lib/serverAudio';
import { authenticateRequest, jsonError } from '@/lib/serverAuth';

export async function POST(request: Request) {
  const auth = await authenticateRequest(request);
  if (auth instanceof Response) return auth;
  if (!auth.identity.userId) return jsonError(403, 'audio upload requires a user');

  const contentType = request.headers.get('content-type') || 'audio/webm';
  const body = await request.arrayBuffer();
  if (!body.byteLength) return jsonError(400, 'empty body');

  const audioPath = await writeTranscriptAudio(auth.identity.userId, body, contentType);
  return Response.json({ path: audioPath });
}
