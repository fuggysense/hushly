const http = require('node:http');
const path = require('node:path');
const { createRequestHandler } = require('expo-server/adapter/http');

const port = Number(process.env.PORT || 3000);
const handler = createRequestHandler({
  build: path.join(__dirname, '../dist/server'),
});

const server = http.createServer((req, res) => {
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
