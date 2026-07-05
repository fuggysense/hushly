const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { WebSocketServer, WebSocket } = require('ws');
const { createRequestHandler } = require('expo-server/adapter/http');

const port = Number(process.env.PORT || 3000);
const clientRoot = path.join(__dirname, '../dist/client');
const handler = createRequestHandler({
  build: path.join(__dirname, '../dist/server'),
});

const server = http.createServer((req, res) => {
  if (serveStaticFile(req, res)) return;

  handler(req, res, (error) => {
    if (error) {
      console.error(error);
      res.statusCode = 500;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ error: 'internal server error' }));
      return;
    }
    res.statusCode = 404;
    res.end('not found');
  });
});

// --- /realtime: live transcription WebSocket proxy -------------------------
// Desktop connects here with X-Hushly-API-Key (or Authorization: Bearer) and
// streams raw linear16 PCM (16 kHz mono) as binary frames. We validate the
// credential against the app's own /auth-check route, open a Deepgram live
// connection, and relay interim/final transcripts back as JSON:
//   { type: 'interim' | 'final', text }   transcript events
//   { type: 'error', error }              fatal errors before close
// Client sends {"type":"finalize"} text frame to flush and end the session.
// Dictionary/keyterm passthrough matches /transcribe: ?replace=find:replace
// and ?keyterm=term query params are forwarded to Deepgram.
const KEYTERM_MAX = 100;
const REPLACE_MAX = 200;

const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  let pathname;
  try {
    pathname = new URL(req.url, 'http://localhost').pathname;
  } catch {
    socket.destroy();
    return;
  }
  if (pathname !== '/realtime') {
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (client) => {
    handleRealtime(client, req).catch((error) => {
      console.error('realtime session error', error);
      closeWith(client, 1011, 'internal error');
    });
  });
});

async function handleRealtime(client, req) {
  const authorized = await checkRealtimeAuth(req);
  if (!authorized) {
    sendJSON(client, { type: 'error', error: 'unauthorized' });
    closeWith(client, 4401, 'unauthorized');
    return;
  }

  const deepgramKey = process.env.DEEPGRAM_API_KEY;
  if (!deepgramKey) {
    sendJSON(client, { type: 'error', error: 'DEEPGRAM_API_KEY not set on server' });
    closeWith(client, 1011, 'server misconfigured');
    return;
  }

  const dg = new WebSocket(buildDeepgramLiveUrl(req.url), {
    headers: { Authorization: `Token ${deepgramKey}` },
  });

  // Audio arriving before Deepgram's socket opens is buffered, not dropped —
  // the first syllable is exactly what users notice going missing. Capped so
  // a stalled upstream can't grow memory unbounded.
  const PENDING_MAX_BYTES = 8 * 1024 * 1024;
  const pending = [];
  let pendingBytes = 0;
  let dgOpen = false;
  // A sub-second dictation can finalize before Deepgram's socket opens —
  // remember it and flush CloseStream right after the buffered audio.
  let finalizePending = false;

  dg.on('open', () => {
    dgOpen = true;
    for (const chunk of pending) dg.send(chunk);
    pending.length = 0;
    pendingBytes = 0;
    if (finalizePending) {
      dg.send(JSON.stringify({ type: 'CloseStream' }));
    }
  });

  dg.on('message', (data) => {
    let event;
    try {
      event = JSON.parse(data.toString());
    } catch {
      return;
    }
    if (event.type !== 'Results') return;
    const text = event.channel?.alternatives?.[0]?.transcript ?? '';
    if (!text) return;
    sendJSON(client, { type: event.is_final ? 'final' : 'interim', text });
  });

  dg.on('close', () => {
    dgOpen = false;
    closeWith(client, 1000, 'done');
  });
  dg.on('error', (error) => {
    dgOpen = false;
    console.error('deepgram live error', error);
    sendJSON(client, { type: 'error', error: 'deepgram connection failed' });
    closeWith(client, 1011, 'upstream error');
  });

  client.on('message', (data, isBinary) => {
    if (isBinary) {
      if (dgOpen && dg.readyState === WebSocket.OPEN) {
        dg.send(data);
      } else if (!dgOpen) {
        pendingBytes += data.length ?? 0;
        if (pendingBytes > PENDING_MAX_BYTES) {
          sendJSON(client, { type: 'error', error: 'upstream not ready' });
          closeWith(client, 1011, 'buffer overflow');
          dg.terminate();
          return;
        }
        pending.push(data);
      }
      // dgOpen but socket closed: session is ending, drop stragglers.
      return;
    }
    let message;
    try {
      message = JSON.parse(data.toString());
    } catch {
      return;
    }
    if (message.type === 'finalize') {
      if (dgOpen && dg.readyState === WebSocket.OPEN) {
        dg.send(JSON.stringify({ type: 'CloseStream' }));
      } else if (!dgOpen) {
        finalizePending = true;
      }
    }
  });

  client.on('error', (error) => {
    console.error('realtime client error', error);
    dg.terminate();
  });

  client.on('close', () => {
    if (dg.readyState === WebSocket.OPEN || dg.readyState === WebSocket.CONNECTING) {
      dg.terminate();
    }
  });
}

async function checkRealtimeAuth(req) {
  const headers = {};
  if (req.headers['x-hushly-api-key']) {
    headers['X-Hushly-API-Key'] = req.headers['x-hushly-api-key'];
  }
  if (req.headers.authorization) {
    headers.Authorization = req.headers.authorization;
  }
  if (Object.keys(headers).length === 0) return false;

  try {
    const response = await fetch(`http://127.0.0.1:${port}/auth-check`, { headers });
    return response.ok;
  } catch (error) {
    console.error('auth-check failed', error);
    return false;
  }
}

function buildDeepgramLiveUrl(requestUrl) {
  const url = new URL('wss://api.deepgram.com/v1/listen');
  // Mirrors DG_BASE_PARAMS in app/transcribe+api.ts, plus streaming params.
  url.searchParams.set('model', 'nova-3');
  url.searchParams.set('language', 'multi');
  url.searchParams.set('smart_format', 'true');
  url.searchParams.set('punctuate', 'true');
  url.searchParams.set('dictation', 'true');
  url.searchParams.set('encoding', 'linear16');
  url.searchParams.set('sample_rate', '16000');
  url.searchParams.set('channels', '1');
  url.searchParams.set('interim_results', 'true');

  let incoming;
  try {
    incoming = new URL(requestUrl, 'http://localhost').searchParams;
  } catch {
    return url.toString();
  }
  for (const v of incoming.getAll('replace').slice(0, REPLACE_MAX)) {
    if (v.trim()) url.searchParams.append('replace', v);
  }
  for (const v of incoming.getAll('keyterm').slice(0, KEYTERM_MAX)) {
    if (v.trim()) url.searchParams.append('keyterm', v);
  }
  return url.toString();
}

function sendJSON(client, payload) {
  if (client.readyState === WebSocket.OPEN) {
    client.send(JSON.stringify(payload));
  }
}

function closeWith(client, code, reason) {
  if (client.readyState === WebSocket.OPEN || client.readyState === WebSocket.CONNECTING) {
    try {
      client.close(code, reason);
    } catch {
      client.terminate();
    }
  }
}

server.listen(port, '0.0.0.0', () => {
  console.log(`hushly listening on :${port}`);
});

function serveStaticFile(req, res) {
  if (!req.url || req.method !== 'GET' && req.method !== 'HEAD') return false;

  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  } catch {
    return false;
  }

  if (pathname === '/') return false;
  const filePath = path.normalize(path.join(clientRoot, pathname));
  if (!filePath.startsWith(clientRoot + path.sep)) return false;

  let stats;
  try {
    stats = fs.statSync(filePath);
  } catch {
    return false;
  }
  if (!stats.isFile()) return false;

  res.statusCode = 200;
  res.setHeader('content-type', contentTypeFor(filePath));
  res.setHeader('content-length', String(stats.size));
  res.setHeader('cache-control', cacheControlFor(filePath));

  if (req.method === 'HEAD') {
    res.end();
    return true;
  }

  fs.createReadStream(filePath).pipe(res);
  return true;
}

function contentTypeFor(filePath) {
  switch (path.extname(filePath).toLowerCase()) {
    case '.css':
      return 'text/css; charset=utf-8';
    case '.html':
      return 'text/html; charset=utf-8';
    case '.js':
      return 'application/javascript; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.svg':
      return 'image/svg+xml';
    case '.ttf':
      return 'font/ttf';
    case '.woff':
      return 'font/woff';
    case '.woff2':
      return 'font/woff2';
    case '.xml':
      return 'application/xml; charset=utf-8';
    case '.zip':
      return 'application/zip';
    default:
      return 'application/octet-stream';
  }
}

function cacheControlFor(filePath) {
  return filePath.includes(`${path.sep}_expo${path.sep}static${path.sep}`)
    ? 'public, max-age=31536000, immutable'
    : 'public, max-age=3600';
}
