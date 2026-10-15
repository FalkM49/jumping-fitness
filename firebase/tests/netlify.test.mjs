// Функции Netlify (functions/netlify/functions/*.mjs): настройки, которые
// Netlify читает из файлов, и ночные задачи по расписанию. HTTP-часть —
// http-api.test.mjs. Запуск: npm run test:netlify.

import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { addDays, clearDb, profile, read, seed, seedSubscription, signUp, startEnv, stopEnv, today } from './helpers.mjs';

const FUNCTIONS = '../../functions/netlify/functions';
let anna, api, expire, flowers;

before(async () => {
  await startEnv();
  anna = await signUp();
  process.env.GCLOUD_PROJECT ??= 'demo-jumping-fitness';
  process.env.FUNCTIONS_EMULATOR ??= 'true';
  [api, expire, flowers] = await Promise.all(
    ['api', 'expire-daily', 'flowers-daily'].map((name) => import(`${FUNCTIONS}/${name}.mjs`)),
  );
});
after(stopEnv);

beforeEach(async () => {
  await clearDb();
  await seed(`users/${anna.uid}`, profile('Анна Смирнова'));
});

describe('функции Netlify', () => {
  it('расписание — как у таймеров Yandex (UTC)', () => {
    assert.deepEqual(api.config, { path: '/api/:fn' });
    assert.equal(expire.config.schedule, '5 21 * * *');
    assert.equal(flowers.config.schedule, '10 21 * * *');
    // Регион не задаём: на бесплатном тарифе Netlify выбор региона запрещён.
    assert.equal(expire.config.region, undefined);
    assert.equal(flowers.config.region, undefined);
  });

  it('expire-daily сжигает истёкшие абонементы', async () => {
    await seedSubscription('old', anna.uid, {
      startDate: addDays(today(), -40),
      endDate: addDays(today(), -1),
      originalEndDate: addDays(today(), -1),
    });
    await expire.default(new Request('http://localhost/', { method: 'POST', body: '{}' }));
    const sub = await read('subscriptions/old');
    assert.equal(sub.trainingsLeft, 0);
    assert.equal(sub.burnedTrainings, 8);
  });

  it('flowers-daily выполняется без ошибок', async () => {
    await flowers.default(new Request('http://localhost/', { method: 'POST', body: '{}' }));
  });

  it('имя функции берётся и из пути, если Netlify не передал параметры', async () => {
    const res = await api.default(
      new Request('http://localhost/api/ensureMonthlyFlower', { method: 'POST', body: '{"data":{}}' }),
    );
    assert.equal(res.status, 401);
    assert.equal((await res.json()).error.status, 'UNAUTHENTICATED');
  });
});
