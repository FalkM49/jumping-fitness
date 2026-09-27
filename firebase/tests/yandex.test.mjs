// Адаптер Yandex Cloud Functions (functions/src/yandex.ts): протокол вызова,
// вход, ошибки и ночные задачи по таймеру. Запуск: npm run test:yandex —
// вместе со всеми тестами функций, которые в этом режиме тоже идут через адаптер.

import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  addDays,
  call,
  clearDb,
  profile,
  read,
  seed,
  seedSubscription,
  signUp,
  startEnv,
  stopEnv,
  today,
} from './helpers.mjs';

const BASE = process.env.CALLABLE_BASE;
let anna, yandex;

before(async () => {
  await startEnv();
  anna = await signUp();
  // Сам модуль — для таймеров: в облаке их вызывает Yandex, не HTTP.
  process.env.GCLOUD_PROJECT ??= 'demo-jumping-fitness';
  process.env.FUNCTIONS_EMULATOR ??= 'true';
  yandex = await import('../../functions/lib/yandex.js');
});
after(stopEnv);

beforeEach(async () => {
  await clearDb();
  await seed(`users/${anna.uid}`, profile('Анна Смирнова'));
});

const raw = (path, init) => fetch(`${BASE}/${path}`, init).then(async (r) => ({ status: r.status, body: await r.json() }));

describe('HTTP: протокол callable', { skip: !BASE && 'только npm run test:yandex' }, () => {
  it('без входа — функция сама отвечает «нужно войти»', async () => {
    const res = await call('ensureMonthlyFlower', {});
    assert.equal(res.error?.status, 'UNAUTHENTICATED');
  });

  it('поддельный токен — 401 до вызова функции', async () => {
    const res = await raw('ensureMonthlyFlower', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer fake-token' },
      body: '{"data":{}}',
    });
    assert.equal(res.status, 401);
    assert.equal(res.body.error.status, 'UNAUTHENTICATED');
  });

  it('неизвестная функция, GET и битое тело — понятные отказы', async () => {
    assert.equal((await raw('dropDatabase', { method: 'POST', body: '{}' })).body.error.status, 'NOT_FOUND');
    assert.equal((await raw('bookTraining', { method: 'GET' })).body.error.status, 'INVALID_ARGUMENT');
    const broken = await raw('bookTraining', { method: 'POST', body: '{не json' });
    assert.equal(broken.status, 400);
    assert.equal(broken.body.error.status, 'INVALID_ARGUMENT');
  });

  it('отказ по правилу — failed-precondition с причиной, как в Firebase', async () => {
    const res = await call('freezeSubscription', { days: 2 }, anna);
    assert.equal(res.error?.status, 'FAILED_PRECONDITION');
    assert.equal(res.error?.details?.reason, 'no_subscription');
    assert.equal(res.error?.message, 'Нет действующего абонемента.');
  });

  it('CORS: веб-версии разрешено, чужому сайту — нет', async () => {
    const preflight = await fetch(`${BASE}/bookTraining`, {
      method: 'OPTIONS',
      headers: { Origin: 'https://jumpingfitness.web.app' },
    });
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get('access-control-allow-origin'), 'https://jumpingfitness.web.app');
    assert.match(preflight.headers.get('access-control-allow-headers') ?? '', /Authorization/);

    const call = await fetch(`${BASE}/ensureMonthlyFlower`, {
      method: 'POST',
      headers: { Origin: 'https://jumpingfitness.web.app', 'Content-Type': 'application/json' },
      body: '{"data":{}}',
    });
    assert.equal(call.headers.get('access-control-allow-origin'), 'https://jumpingfitness.web.app');

    const foreign = await fetch(`${BASE}/bookTraining`, {
      method: 'OPTIONS',
      headers: { Origin: 'https://evil.example' },
    });
    assert.equal(foreign.headers.get('access-control-allow-origin'), null);
  });

  it('64-битные числа от телефона разворачиваются', async () => {
    await seedSubscription('sub_anna', anna.uid);
    const res = await call(
      'freezeSubscription',
      { days: { '@type': 'type.googleapis.com/google.protobuf.Int64Value', value: '2' } },
      anna,
    );
    assert.equal(res.result?.freeze?.days, 2);
  });
});

describe('таймеры Yandex Cloud', () => {
  it('payload = имя задачи: expireSubscriptionsDaily сжигает истёкшие', async () => {
    await seedSubscription('old', anna.uid, {
      startDate: addDays(today(), -40),
      endDate: addDays(today(), -1),
      originalEndDate: addDays(today(), -1),
    });
    const res = await yandex.handler({
      messages: [{ details: { payload: 'expireSubscriptionsDaily', trigger_id: 't' } }],
    });
    assert.deepEqual(res, { ran: ['expireSubscriptionsDaily'] });
    const sub = await read('subscriptions/old');
    assert.equal(sub.trainingsLeft, 0);
    assert.equal(sub.burnedTrainings, 8);
  });

  it('неизвестная задача пропускается, остальные выполняются', async () => {
    const res = await yandex.handler({
      messages: [{ details: { payload: 'rm -rf' } }, { details: { payload: 'assignMonthlyFlowers' } }],
    });
    assert.deepEqual(res.ran, ['assignMonthlyFlowers']);
  });

  it('decode: вложенные обёртки чисел', () => {
    const wrapped = { '@type': 'type.googleapis.com/google.protobuf.Int64Value', value: '7' };
    assert.deepEqual(yandex.decode({ a: [wrapped], b: { c: wrapped }, d: 'x' }), { a: [7], b: { c: 7 }, d: 'x' });
  });
});
