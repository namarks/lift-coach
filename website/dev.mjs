import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { homePage } from './home.mjs';
import { PRIVACY_HTML } from './privacy.mjs';

const assetRoot = new URL('./public/assets/', import.meta.url);
const types = { '.png': 'image/png', '.ttf': 'font/ttf', '.txt': 'text/plain; charset=utf-8' };
const server = createServer(async (req, res) => {
  const path = new URL(req.url, 'http://localhost').pathname;
  if (path === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(homePage());
  } else if (path === '/privacy' || path === '/privacy/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(PRIVACY_HTML);
  } else if (/^\/assets\/[a-zA-Z0-9._-]+$/.test(path)) {
    try {
      const body = await readFile(new URL(path.slice('/assets/'.length), assetRoot));
      const ext = path.slice(path.lastIndexOf('.'));
      res.writeHead(200, { 'Content-Type': types[ext] ?? 'application/octet-stream' });
      res.end(body);
    } catch { res.writeHead(404); res.end('Not found'); }
  } else { res.writeHead(404); res.end('Not found'); }
});
server.listen(4321, '127.0.0.1', () => console.log('Local: http://127.0.0.1:4321'));
