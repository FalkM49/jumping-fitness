// Адаптер Yandex Cloud Functions (functions/src/yandex.ts): ночные задачи по
// таймеру и разбор чисел. HTTP-часть — http-api.test.mjs.
// Запуск: npm run test:yandex.

import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { addDays, clearDb, profile, read, seed, seedSubscription, signUp, startEnv, stopEnv, today } from './helpers.mjs';

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
