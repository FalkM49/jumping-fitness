// Функция Netlify (netlify/functions/api.mjs) как обычный HTTP-сервер на этом
// компьютере — поверх ЛОКАЛЬНЫХ эмуляторов Auth и Firestore. Запрос
// переводится в Web Request, как это делает Netlify.
//
//   npm run dev:api:netlify          порт 5003, эмуляторы для разработки
//   PORT=5103 … node scripts/netlify-local.mjs
//
// Адрес, как в облаке: POST http://127.0.0.1:5003/api/bookTraining

import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
process.env.GCLOUD_PROJECT ??= 'demo-jumping-fitness';
// Как в эмуляторе Functions: push через FCM не отправляются.
process.env.FUNCTIONS_EMULATOR ??= 'true';

// NETLIFY_API_ENTRY — путь к другой точке входа, например к api.mjs из
// архива, который собрал упаковщик Netlify (@netlify/zip-it-and-ship-it).
const entry = process.env.NETLIFY_API_ENTRY
  ? pathToFileURL(process.env.NETLIFY_API_ENTRY).href
  : '../netlify/functions/api.mjs';
const { default: api, config } = await import(entry);
const port = Number(process.env.PORT ?? 5003);
// '/api/:fn' → /^\/api\/([^/]+)$/
const route = new RegExp(`^${(config?.path ?? '/api/:fn').replace(/:(\w+)/, '([^/]+)')}$`);

createServer(async (req, res) => {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const url = new URL(req.url ?? '/', `http://127.0.0.1:${port}`);
  const match = url.pathname.match(route);
  if (!match) {
    res.writeHead(404).end('Not Found');
    return;
  }

  const started = Date.now();
  const body = Buffer.concat(chunks);
  const request = new Request(url, {
    method: req.method,
    headers: Object.entries(req.headers).map(([k, v]) => [k, Array.isArray(v) ? v.join(',') : (v ?? '')]),
    body: ['GET', 'HEAD'].includes(req.method ?? '') ? undefined : body,
  });
  const response = await api(request, { params: { fn: decodeURIComponent(match[1]) } });
  res.writeHead(response.status, Object.fromEntries(response.headers));
  res.end(Buffer.from(await response.arrayBuffer()));
  console.log(`${req.method} ${url.pathname} → ${response.status} (${Date.now() - started} мс)`);
}).listen(port, '127.0.0.1', () => {
  console.log(`Адаптер Netlify слушает http://127.0.0.1:${port}/api (Firestore ${process.env.FIRESTORE_EMULATOR_HOST})`);
});
