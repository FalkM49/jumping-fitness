// Прогон тестов функций через адаптер Yandex Cloud (npm run test:yandex).
// Запускается внутри `emulators:exec` (Auth + Firestore, без эмулятора
// Functions): поднимает functions/scripts/yandex-local.mjs и гонит тесты,
// направив вызовы на него.

import { spawn } from 'node:child_process';

const PORT = 5102;
const tests = process.argv.slice(2);

const server = spawn(process.execPath, ['../../functions/scripts/yandex-local.mjs'], {
  env: { ...process.env, PORT: String(PORT) },
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
  env: { ...process.env, CALLABLE_BASE: `http://127.0.0.1:${PORT}` },
  stdio: 'inherit',
});
const code = await new Promise((resolve) => run.on('exit', resolve));
server.kill();
process.exit(code ?? 1);
