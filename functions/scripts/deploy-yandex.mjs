// Выкладка серверных функций в Yandex Cloud Functions.
//
//   npm run deploy:yc                          код (новая версия функции)
//   npm run deploy:yc -- --key E:\keys\jf.json  + ключ Firebase в секрет Lockbox
//
// Нужны: `yc init` (облако и каталог выбраны) и собранный код (скрипт
// соберёт сам). Повторный запуск безопасен: что уже есть — не создаётся
// заново, выкладывается только новая версия кода.
//
// Что создаётся в каталоге Yandex Cloud:
//   • сервисный аккаунт jf-functions — функция читает секрет, таймеры
//     вызывают функцию;
//   • секрет Lockbox firebase-service-account — ключ доступа к Firebase
//     (из файла --key; ключ никуда не выводится);
//   • функция jumping-fitness-api (Node.js 22) — публичная: вход проверяет
//     сама по токену Firebase Auth;
//   • таймеры: 00:05 МСК — сгорание тренировок и напоминания,
//     00:10 МСК — цветок месяца (задача сама ничего не меняет, если цветок
//     на этот месяц уже есть).

import { execFileSync } from 'node:child_process';
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const FUNCTION = 'jumping-fitness-api';
const SERVICE_ACCOUNT = 'jf-functions';
const SECRET = 'firebase-service-account';
const GATEWAY = 'jumping-fitness-gateway';
// Cron Yandex — по UTC: 21:05 UTC = 00:05 МСК.
const TIMERS = [
  { name: 'jf-expire-daily', cron: '5 21 ? * * *', payload: 'expireSubscriptionsDaily' },
  { name: 'jf-flowers-daily', cron: '10 21 ? * * *', payload: 'assignMonthlyFlowers' },
];

const root = fileURLToPath(new URL('..', import.meta.url));
const args = process.argv.slice(2);
const keyIndex = args.indexOf('--key');
const keyPath = keyIndex === -1 ? null : args[keyIndex + 1];

if (process.platform === 'win32') {
  process.env.PATH = `${process.env.USERPROFILE}\\yandex-cloud\\bin;${process.env.PATH}`;
}

function yc(argv, input) {
  const out = execFileSync(process.platform === 'win32' ? 'yc.exe' : 'yc', [...argv, '--format', 'json'], {
    encoding: 'utf8',
    input,
    stdio: ['pipe', 'pipe', 'inherit'],
    maxBuffer: 16 * 1024 * 1024,
  });
  return out.trim() ? JSON.parse(out) : null;
}

const find = (list, name) => (list ?? []).find((item) => item.name === name) ?? null;
const step = (text) => console.log(`\n▸ ${text}`);

// 1. Сервисный аккаунт и его роли в каталоге.
const folderId = execFileSync(process.platform === 'win32' ? 'yc.exe' : 'yc', ['config', 'get', 'folder-id'], {
  encoding: 'utf8',
}).trim();
step(`Каталог ${folderId}: сервисный аккаунт ${SERVICE_ACCOUNT}`);
let sa = find(yc(['iam', 'service-account', 'list']), SERVICE_ACCOUNT);
if (!sa) {
  sa = yc(['iam', 'service-account', 'create', '--name', SERVICE_ACCOUNT,
    '--description', 'Jumping Fitness: чтение секрета Firebase, вызов функции таймерами']);
  console.log('  создан');
}
for (const role of ['lockbox.payloadViewer', 'functions.functionInvoker']) {
  yc(['resource-manager', 'folder', 'add-access-binding', folderId,
    '--role', role, '--subject', `serviceAccount:${sa.id}`]);
}

// 2. Секрет с ключом Firebase.
step(`Секрет ${SECRET}`);
let secret = find(yc(['lockbox', 'secret', 'list']), SECRET);
if (keyPath) {
  const key = readFileSync(resolve(keyPath), 'utf8');
  const parsed = JSON.parse(key);
  if (parsed.type !== 'service_account' || !parsed.project_id) {
    console.error('Файл --key не похож на ключ сервисного аккаунта Firebase.');
    process.exit(1);
  }
  const payload = JSON.stringify([{ key: 'json', text_value: key }]);
  if (secret) {
    yc(['lockbox', 'secret', 'add-version', '--id', secret.id, '--payload', '-'], payload);
    console.log(`  новая версия (проект ${parsed.project_id})`);
  } else {
    secret = yc(['lockbox', 'secret', 'create', '--name', SECRET, '--payload', '-',
      '--description', 'Ключ сервисного аккаунта Firebase для функций Jumping Fitness'], payload);
    console.log(`  создан (проект ${parsed.project_id})`);
  }
} else if (secret) {
  console.log('  есть');
} else {
  console.log('  нет — функция выйдет без доступа к Firebase (для проверки запуска).');
  console.log('  Передайте ключ: npm run deploy:yc -- --key <путь к ключу>.json');
}

// 3. Код: сборка и папка для загрузки — только lib/ и зависимости.
step('Сборка кода');
execFileSync(process.platform === 'win32' ? 'npm.cmd' : 'npm', ['run', 'build'], {
  cwd: root, stdio: 'inherit', shell: process.platform === 'win32',
});
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const stage = join(tmpdir(), 'jumping-fitness-yc');
rmSync(stage, { recursive: true, force: true });
mkdirSync(stage);
cpSync(join(root, 'lib'), join(stage, 'lib'), { recursive: true });
// Firestore у firebase-admin — необязательная зависимость, а npm в Yandex
// такие не ставит: указываем её явно, той же версии, что проверена тестами.
const installed = (name) =>
  JSON.parse(readFileSync(join(root, 'node_modules', name, 'package.json'), 'utf8')).version;
writeFileSync(join(stage, 'package.json'), JSON.stringify({
  name: pkg.name,
  private: true,
  type: 'module',
  dependencies: {
    ...pkg.dependencies,
    '@google-cloud/firestore': installed('@google-cloud/firestore'),
  },
}, null, 2));

// 4. Функция и новая версия.
step(`Функция ${FUNCTION}`);
let fn = find(yc(['serverless', 'function', 'list']), FUNCTION);
if (!fn) {
  fn = yc(['serverless', 'function', 'create', '--name', FUNCTION,
    '--description', 'Jumping Fitness: бизнес-логика (запись, абонементы, уведомления)']);
  console.log('  создана');
}
// Напрямую функцию не вызвать: только через шлюз (п. 6) и таймеры —
// от имени сервисного аккаунта.
yc(['serverless', 'function', 'deny-unauthenticated-invoke', FUNCTION]);

const versionArgs = ['serverless', 'function', 'version', 'create',
  '--function-id', fn.id,
  '--runtime', 'nodejs22',
  '--entrypoint', 'lib/yandex.handler',
  '--memory', '256MB',
  '--execution-timeout', '30s',
  '--service-account-id', sa.id,
  '--source-path', stage,
];
if (secret) {
  versionArgs.push('--secret', `id=${secret.id},key=json,environment-variable=FIREBASE_SERVICE_ACCOUNT`);
}
const version = yc(versionArgs);
console.log(`  версия ${version.id} выложена`);

// 5. Таймеры ночных задач.
step('Таймеры');
const triggers = yc(['serverless', 'trigger', 'list']);
for (const timer of TIMERS) {
  if (find(triggers, timer.name)) {
    console.log(`  ${timer.name}: есть`);
    continue;
  }
  yc(['serverless', 'trigger', 'create', 'timer', '--name', timer.name,
    '--cron-expression', timer.cron, '--payload', timer.payload,
    '--invoke-function-id', fn.id, '--invoke-function-service-account-id', sa.id,
    '--retry-attempts', '3', '--retry-interval', '60s']);
  console.log(`  ${timer.name}: создан (${timer.payload})`);
}

// 6. API Gateway: публичный адрес для приложения. Передаёт заголовки
// (с токеном Firebase) функции как есть; вход проверяет сама функция.
step(`API Gateway ${GATEWAY}`);
const spec = join(stage, 'gateway.yaml');
writeFileSync(spec, `openapi: 3.0.0
info:
  title: ${GATEWAY}
  version: 1.0.0
paths:
  /{fn}:
    post:
      parameters:
        - name: fn
          in: path
          required: true
          schema:
            type: string
      x-yc-apigateway-integration:
        type: cloud_functions
        function_id: ${fn.id}
        service_account_id: ${sa.id}
`);
let gateway = find(yc(['serverless', 'api-gateway', 'list']), GATEWAY);
if (gateway) {
  gateway = yc(['serverless', 'api-gateway', 'update', '--id', gateway.id, '--spec', spec]);
  console.log('  обновлён');
} else {
  gateway = yc(['serverless', 'api-gateway', 'create', '--name', GATEWAY, '--spec', spec,
    '--description', 'Jumping Fitness: вызовы функций из приложения']);
  console.log('  создан');
}

rmSync(stage, { recursive: true, force: true });
console.log(`\nГотово. Адрес для приложения (FUNCTIONS_API_URL):\n  https://${gateway.domain}`);
