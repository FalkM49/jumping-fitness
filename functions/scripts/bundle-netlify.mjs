// Сборка сервера для Netlify в один файл: netlify/bundle/netlify.cjs
// (npm run build:netlify; Netlify запускает это сам — netlify.toml).
//
// Зачем: firebase-admin 14 → jwks-rsa 4 загружает ES-модуль jose через
// require(). Это умеет только Node 20.19+ / 22.12+, а функции Netlify
// падали с ERR_REQUIRE_ESM. esbuild переводит всё в CommonJS заранее,
// и сервер не зависит от версии Node на Netlify.
//
// В файл входит всё, включая Firestore: упаковщик Netlify для функций
// нового формата (nft) не кладёт рядом пакеты, которые не вошли в файл
// (было «Cannot find module '@google-cloud/firestore'»), а external_node_modules
// для него не действует. Проверено: npm run test:netlify на api.mjs из архива
// @netlify/zip-it-and-ship-it (NETLIFY_API_ENTRY, scripts/netlify-local.mjs).

import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));

await build({
  absWorkingDir: root,
  entryPoints: ['lib/netlify.js'],
  outfile: 'netlify/bundle/netlify.cjs',
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: 'node20',
  logLevel: 'warning',
});
console.log('Готово: netlify/bundle/netlify.cjs');
