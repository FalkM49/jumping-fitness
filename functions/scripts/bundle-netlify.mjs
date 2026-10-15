// Сборка сервера для Netlify в один файл: netlify/bundle/netlify.cjs
// (npm run build:netlify; Netlify запускает это сам — netlify.toml).
//
// Зачем: firebase-admin 14 → jwks-rsa 4 загружает ES-модуль jose через
// require(). Это умеет только Node 20.19+ / 22.12+, а функции Netlify
// падали с ERR_REQUIRE_ESM. esbuild переводит всё в CommonJS заранее,
// и сервер не зависит от версии Node на Netlify.
//
// Firestore остаётся отдельным пакетом из node_modules: он читает свои
// proto-файлы с диска, в один файл его не собрать.

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
  external: ['@google-cloud/firestore'],
  logLevel: 'warning',
});
console.log('Готово: netlify/bundle/netlify.cjs');
