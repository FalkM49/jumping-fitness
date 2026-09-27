// Цветок месяца (ТЗ 4): назначается раз в месяц, не повторяется три месяца подряд.

import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { call, clearDb, profile, read, seed, signUp, startEnv, stopEnv, today } from './helpers.mjs';

let anna;

before(async () => {
  await startEnv();
  anna = await signUp();
});
after(stopEnv);

const month = () => today().slice(0, 7);
const previousMonth = () => {
  const [y, m] = month().split('-').map(Number);
  return m === 1 ? `${y - 1}-12` : `${y}-${String(m - 1).padStart(2, '0')}`;
};

beforeEach(async () => {
  await clearDb();
  for (const id of ['peony', 'rose', 'tulip']) await seed(`flowers/${id}`, { name: id, order: 1 });
});

describe('ensureMonthlyFlower', () => {
  it('новому пользователю — цветок на текущий месяц; повторный вызов его не меняет', async () => {
    await seed(`users/${anna.uid}`, profile('Анна Смирнова'));
    const first = await call('ensureMonthlyFlower', {}, anna);
    assert.equal(first.result.month, month());
    assert.ok(['peony', 'rose', 'tulip'].includes(first.result.flowerId));

    const user = await read(`users/${anna.uid}`);
    assert.deepEqual(user.monthlyFlower, { month: month(), flowerId: first.result.flowerId });
    assert.deepEqual(user.recentFlowerIds, []);

    for (let i = 0; i < 3; i++) {
      assert.equal((await call('ensureMonthlyFlower', {}, anna)).result.flowerId, first.result.flowerId);
    }
  });

  it('не повторяет цветки двух предыдущих месяцев', async () => {
    // Прошлый месяц — роза, позапрошлый — пион: остаётся только тюльпан.
    for (let i = 0; i < 5; i++) {
      await seed(`users/${anna.uid}`, profile('Анна Смирнова', 'client', {
        monthlyFlower: { month: previousMonth(), flowerId: 'rose' },
        recentFlowerIds: ['peony'],
      }));
      const res = await call('ensureMonthlyFlower', {}, anna);
      assert.equal(res.result.flowerId, 'tulip');
    }
    const user = await read(`users/${anna.uid}`);
    assert.deepEqual(user.recentFlowerIds, ['rose', 'peony']);
  });

  it('без входа — отказ', async () => {
    assert.equal((await call('ensureMonthlyFlower', {})).error?.status, 'UNAUTHENTICATED');
  });
});
