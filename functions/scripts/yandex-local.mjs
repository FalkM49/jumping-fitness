// Адаптер Yandex Cloud (lib/yandex.js) как обычный HTTP-сервер на этом
// компьютере — поверх ЛОКАЛЬНЫХ эмуляторов Auth и Firestore. Запрос
// переводится в формат Yandex Cloud Functions, как это делает облако.
//
//   npm run dev:api                  порт 5002, эмуляторы для разработки
//   PORT=5102 FIRESTORE_EMULATOR_HOST=127.0.0.1:8180 … node scripts/yandex-local.mjs
//
// Имя функции — из ?fn=… или последнего сегмента пути:
//   POST http://127.0.0.1:5002/bookTraining  ≡  POST …/?fn=bookTraining

import { createServer } from 'node:http';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
process.env.GCLOUD_PROJECT ??= 'demo-jumping-fitness';
// Как в эмуляторе Functions: push через FCM не отправляются.
process.env.FUNCTIONS_EMULATOR ??= 'true';

const { handler } = await import('../lib/yandex.js');
const port = Number(process.env.PORT ?? 5002);

createServer(async (req, res) => {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const url = new URL(req.url ?? '/', 'http://localhost');
  const query = Object.fromEntries(url.searchParams);
  query.fn ??= url.pathname.split('/').filter(Boolean).at(-1);

  const response = await handler({
    httpMethod: req.method,
    headers: Object.fromEntries(
      Object.entries(req.headers).map(([k, v]) => [k, Array.isArray(v) ? v.join(',') : v]),
    ),
    queryStringParameters: query,
    body: Buffer.concat(chunks).toString('utf8'),
    isBase64Encoded: false,
  });
  res.writeHead(response.statusCode, response.headers);
  res.end(response.body);
}).listen(port, '127.0.0.1', () => {
  console.log(`Адаптер Yandex слушает http://127.0.0.1:${port} (Firestore ${process.env.FIRESTORE_EMULATOR_HOST})`);
});
