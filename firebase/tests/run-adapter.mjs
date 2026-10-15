// Прогон тестов функций через адаптер площадки:
//   node run-adapter.mjs yandex  <тесты…>   (npm run test:yandex)
//   node run-adapter.mjs netlify <тесты…>   (npm run test:netlify)
// Запускается внутри `emulators:exec` (Auth + Firestore, без эмулятора
// Functions): поднимает локальный сервер адаптера и гонит тесты, направив
// вызовы на него.

import { spawn } from 'node:child_process';

const adapters = {
  yandex: { port: 5102, script: '../../functions/scripts/yandex-local.mjs', base: '' },
  netlify: { port: 5103, script: '../../functions/scripts/netlify-local.mjs', base: '/api' },
};
const [name, ...tests] = process.argv.slice(2);
const adapter = adapters[name];
if (!adapter) throw new Error(`Неизвестный адаптер «${name}»: ${Object.keys(adapters).join(', ')}`);

const server = spawn(process.execPath, [adapter.script], {
  env: { ...process.env, PORT: String(adapter.port) },
  stdio: ['ignore', 'pipe', 'inherit'],
});

await new Promise((resolve, reject) => {
  server.stdout.on('data', (chunk) => {
    process.stdout.write(chunk);
    if (String(chunk).includes('слушает')) resolve();
  });
  server.on('exit', (code) => reject(new Error(`Адаптер завершился с кодом ${code}`)));
});

const run = spawn(process.execPath, ['--test', '--test-concurrency=1', ...tests], {
  env: {
    ...process.env,
    ADAPTER: name,
    CALLABLE_BASE: `http://127.0.0.1:${adapter.port}${adapter.base}`,
  },
  stdio: 'inherit',
});
const code = await new Promise((resolve) => run.on('exit', resolve));
server.kill();
process.exit(code ?? 1);
