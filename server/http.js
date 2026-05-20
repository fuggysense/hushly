const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
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
