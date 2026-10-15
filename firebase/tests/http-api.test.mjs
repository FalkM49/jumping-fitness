// HTTP API серверных функций (functions/src/http_api.ts) через адаптер
// площадки: протокол вызова, вход, ошибки, CORS. Запуск: npm run test:yandex
// или npm run test:netlify — вместе со всеми тестами функций, которые в этом
// режиме тоже идут через адаптер.

import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { call, clearDb, profile, seed, seedSubscription, signUp, startEnv, stopEnv } from './helpers.mjs';

const BASE = process.env.CALLABLE_BASE;
let anna;

before(async () => {
  await startEnv();
  anna = await signUp();
});
after(stopEnv);

beforeEach(async () => {
  await clearDb();
  await seed(`users/${anna.uid}`, profile('Анна Смирнова'));
});

const raw = (path, init) => fetch(`${BASE}/${path}`, init).then(async (r) => ({ status: r.status, body: await r.json() }));

describe(`HTTP: протокол callable (${process.env.ADAPTER})`, { skip: !BASE && 'только через адаптер' }, () => {
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
    assert.equal(
      (await raw('toString', { method: 'POST', body: '{}' })).body.error.status,
      'NOT_FOUND',
      'имя из Object.prototype — тоже не функция',
    );
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

    const preview = await fetch(`${BASE}/bookTraining`, {
      method: 'OPTIONS',
      headers: { Origin: 'https://jumpingfitness--iphone-fix-a1b2c3d4.web.app' },
    });
    assert.equal(
      preview.headers.get('access-control-allow-origin'),
      'https://jumpingfitness--iphone-fix-a1b2c3d4.web.app',
      'канал предпросмотра Firebase Hosting',
    );
    const lookalike = await fetch(`${BASE}/bookTraining`, {
      method: 'OPTIONS',
      headers: { Origin: 'https://jumpingfitness.web.app.evil.example' },
    });
    assert.equal(lookalike.headers.get('access-control-allow-origin'), null);

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
