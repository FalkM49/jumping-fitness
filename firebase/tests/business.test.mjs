// Тесты бизнес-логики Cloud Functions (ТЗ 3, 5, 6, 8) на эмуляторах.
// Запуск: cd firebase/tests && npm run test:functions
//
// Время — настоящее серверное: тренировки создаются относительно «сейчас»
// (через 2 ч, через 4 ч, завтра), как их увидит функция.

import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  Timestamp,
  addDays,
  call,
  clearDb,
  hours,
  isoWeekday,
  nextDay,
  profile,
  read,
  readAll,
  reason,
  seed,
  seedSubscription,
  seedTraining,
  signUp,
  startEnv,
  stopEnv,
  today,
} from './helpers.mjs';

let anna, olga, ira, trainer, admin;

before(async () => {
  await startEnv();
  [anna, olga, ira, trainer, admin] = await Promise.all([
    signUp(), signUp(), signUp(), signUp(), signUp(),
  ]);
});

after(stopEnv);

beforeEach(async () => {
  await clearDb();
  await seed(`users/${anna.uid}`, profile('Анна Смирнова'));
  await seed(`users/${olga.uid}`, profile('Ольга Петрова'));
  await seed(`users/${ira.uid}`, profile('Ирина Волкова'));
  await seed(`users/${trainer.uid}`, profile('Мария Ковалёва', 'trainer'));
  await seed(`users/${admin.uid}`, profile('Разработчик', 'client', { isAdmin: true }));
  await seedSubscription('sub_anna', anna.uid);
});

// Дни без тренировок по умолчанию (пн/ср/пт) — для «ручных» ячеек.
const offDay = () => nextDay([2, 4, 6, 7]);
const defaultDay = () => nextDay([1, 3, 5]);

// ============================================================================
describe('bookTraining — запись', () => {
  it('успех: место +1, тренировка −1, запись active с абонементом', async () => {
    await seedTraining('t1', hours(24), { bookedCount: 4 });
    const res = await call('bookTraining', { trainingId: 't1' }, anna);
    assert.deepEqual(res.result, { trainingId: 't1', bookedCount: 5, trainingsLeft: 7 });

    assert.equal((await read('trainings/t1')).bookedCount, 5);
    assert.equal((await read('subscriptions/sub_anna')).trainingsLeft, 7);
    const booking = await read(`trainings/t1/bookings/${anna.uid}`);
    assert.equal(booking.status, 'active');
    assert.equal(booking.clientId, anna.uid);
    assert.equal(booking.clientName, 'Анна Смирнова');
    assert.equal(booking.subscriptionId, 'sub_anna');
    assert.ok(booking.bookedAt instanceof Timestamp);
  });

  it('тренировка по расписанию: документ и ячейка создаются при первой записи', async () => {
    const date = defaultDay();
    const res = await call('bookTraining', { date, slot: 'evening' }, anna);
    const id = `default_${date}_evening`;
    assert.equal(res.result?.trainingId, id);

    const training = await read(`trainings/${id}`);
    assert.equal(training.source, 'default');
    assert.equal(training.startTime, '18:00');
    assert.equal(training.capacity, 13);
    assert.equal(training.bookedCount, 1);
    assert.equal(training.createdBy, null);
    assert.equal((await read(`calendar_slots/${date}_evening`)).activeTrainingId, id);

    // Вторая запись идёт в тот же документ, а не создаёт новый.
    await seedSubscription('sub_olga', olga.uid);
    await call('bookTraining', { date, slot: 'evening' }, olga);
    assert.equal((await read(`trainings/${id}`)).bookedCount, 2);
  });

  it('в пустой ячейке тренировки нет', async () => {
    const res = await call('bookTraining', { date: offDay(), slot: 'morning' }, anna);
    assert.equal(reason(res), 'no_training');
  });

  it('дважды на одну тренировку — нельзя, счётчики не меняются', async () => {
    await seedTraining('t1', hours(24));
    await call('bookTraining', { trainingId: 't1' }, anna);
    const res = await call('bookTraining', { trainingId: 't1' }, anna);
    assert.equal(reason(res), 'already_booked');
    assert.equal((await read('trainings/t1')).bookedCount, 1);
    assert.equal((await read('subscriptions/sub_anna')).trainingsLeft, 7);
  });

  it('нет мест', async () => {
    await seedTraining('t1', hours(24), { capacity: 3, bookedCount: 3 });
    const res = await call('bookTraining', { trainingId: 't1' }, anna);
    assert.equal(reason(res), 'full');
    assert.equal((await read('subscriptions/sub_anna')).trainingsLeft, 8);
  });

  it('последнее место при одновременной записи получает ровно один', async () => {
    await seedTraining('t1', hours(24), { capacity: 2, bookedCount: 1 });
    await seedSubscription('sub_olga', olga.uid);
    await seedSubscription('sub_ira', ira.uid);
    const results = await Promise.all(
      [anna, olga, ira].map((u) => call('bookTraining', { trainingId: 't1' }, u)),
    );
    assert.equal(results.filter((r) => r.result).length, 1);
    assert.equal(results.filter((r) => reason(r) === 'full').length, 2);
    assert.equal((await read('trainings/t1')).bookedCount, 2);
  });

  it('без абонемента', async () => {
    await seedTraining('t1', hours(24));
    const res = await call('bookTraining', { trainingId: 't1' }, olga);
    assert.equal(reason(res), 'no_subscription');
  });

  it('абонемент истёк по сроку', async () => {
    await seedTraining('t1', hours(24));
    await seedSubscription('sub_anna', anna.uid, {
      startDate: addDays(today(), -31),
      endDate: addDays(today(), -1),
    });
    assert.equal(reason(await call('bookTraining', { trainingId: 't1' }, anna)), 'subscription_expired');
  });

  it('абонемент ещё не начался', async () => {
    await seedTraining('t1', hours(24));
    await seedSubscription('sub_anna', anna.uid, {
      startDate: addDays(today(), 3),
      endDate: addDays(today(), 33),
    });
    assert.equal(reason(await call('bookTraining', { trainingId: 't1' }, anna)), 'subscription_not_started');
  });

  it('тренировка позже окончания абонемента', async () => {
    await seedTraining('t1', hours(24 * 3));
    await seedSubscription('sub_anna', anna.uid, { endDate: addDays(today(), 1) });
    assert.equal(reason(await call('bookTraining', { trainingId: 't1' }, anna)), 'outside_subscription');
  });

  it('идёт заморозка', async () => {
    await seedTraining('t1', hours(24));
    await seedSubscription('sub_anna', anna.uid, {
      freeze: { startDate: today(), endDate: addDays(today(), 2), days: 3 },
    });
    assert.equal(reason(await call('bookTraining', { trainingId: 't1' }, anna)), 'frozen');
  });

  it('тренировки на абонементе закончились', async () => {
    await seedTraining('t1', hours(24));
    await seedSubscription('sub_anna', anna.uid, { trainingsLeft: 0 });
    assert.equal(reason(await call('bookTraining', { trainingId: 't1' }, anna)), 'no_trainings_left');
  });

  it('чужой абонемент в профиле не принимается', async () => {
    await seedTraining('t1', hours(24));
    const user = await read(`users/${olga.uid}`);
    await seed(`users/${olga.uid}`, { ...user, currentSubscriptionId: 'sub_anna' });
    assert.equal(reason(await call('bookTraining', { trainingId: 't1' }, olga)), 'no_subscription');
  });

  it('началась, отменена — записаться нельзя', async () => {
    await seedTraining('started', -hours(0.5));
    assert.equal(reason(await call('bookTraining', { trainingId: 'started' }, anna)), 'training_started');
    await seedTraining('gone', hours(30), { status: 'cancelled' });
    assert.equal(reason(await call('bookTraining', { trainingId: 'gone' }, anna)), 'training_cancelled');
  });

  it('тренер не записывается; без входа — отказ; кривые аргументы — отказ', async () => {
    await seedTraining('t1', hours(24));
    assert.equal(reason(await call('bookTraining', { trainingId: 't1' }, trainer)), 'trainer_cannot_book');
    assert.equal((await call('bookTraining', { trainingId: 't1' })).error?.status, 'UNAUTHENTICATED');
    for (const data of [null, {}, { trainingId: '' }, { date: '2026-02-30', slot: 'morning' }, { date: today(), slot: 'night' }]) {
      assert.equal((await call('bookTraining', data, anna)).error?.status, 'INVALID_ARGUMENT', JSON.stringify(data));
    }
    assert.equal((await call('bookTraining', { trainingId: 'nope' }, anna)).error?.status, 'NOT_FOUND');
  });
});

// ============================================================================
describe('cancelBooking — отмена клиентом (правило 3 часов)', () => {
  it('больше чем за 3 часа: возврат тренировки, место освобождается, можно снова', async () => {
    await seedTraining('t1', hours(4), { bookedCount: 2 });
    await call('bookTraining', { trainingId: 't1' }, anna);

    const res = await call('cancelBooking', { trainingId: 't1' }, anna);
    assert.deepEqual(res.result, { trainingId: 't1', refunded: true });
    assert.equal((await read(`trainings/t1/bookings/${anna.uid}`)).status, 'cancelled_by_client');
    assert.equal((await read('trainings/t1')).bookedCount, 2);
    assert.equal((await read('subscriptions/sub_anna')).trainingsLeft, 8);

    assert.ok((await call('bookTraining', { trainingId: 't1' }, anna)).result);
  });

  it('3 часа и меньше — отмена недоступна', async () => {
    await seedTraining('soon', hours(3) - 60_000);
    await call('bookTraining', { trainingId: 'soon' }, anna);
    const res = await call('cancelBooking', { trainingId: 'soon' }, anna);
    assert.equal(reason(res), 'cancel_window_passed');
    assert.equal((await read(`trainings/soon/bookings/${anna.uid}`)).status, 'active');
    assert.equal((await read('subscriptions/sub_anna')).trainingsLeft, 7);
  });

  it('граница: ровно за 3 часа — уже нельзя, за 3 ч 2 мин — ещё можно', async () => {
    // Документ создаётся ровно за 3 ч; к моменту вызова до начала уже
    // не больше 3 ч — это и есть граница «ровно 3 часа» (ТЗ 3.1).
    await seedTraining('edge', hours(3));
    await call('bookTraining', { trainingId: 'edge' }, anna);
    assert.equal(reason(await call('cancelBooking', { trainingId: 'edge' }, anna)), 'cancel_window_passed');

    await seedTraining('ok', hours(3) + 120_000);
    await call('bookTraining', { trainingId: 'ok' }, anna);
    assert.ok((await call('cancelBooking', { trainingId: 'ok' }, anna)).result);
  });

  it('нельзя отменить то, на что не записан', async () => {
    await seedTraining('t1', hours(24));
    assert.equal(reason(await call('cancelBooking', { trainingId: 't1' }, anna)), 'not_booked');
  });

  it('абонемент продлили после записи — тренировка возвращается в новый', async () => {
    await seedTraining('t1', hours(24));
    await call('bookTraining', { trainingId: 't1' }, anna);
    const renewed = await call('renewSubscription', {
      clientId: anna.uid, startDate: today(), endDate: addDays(today(), 29), trainings: 11, freezeLimitDays: 3,
    }, trainer);

    await call('cancelBooking', { trainingId: 't1' }, anna);
    assert.equal((await read('subscriptions/sub_anna')).trainingsLeft, 7);
    assert.equal((await read(`subscriptions/${renewed.result.subscriptionId}`)).trainingsLeft, 12);
  });
});

// ============================================================================
describe('removeClientFromTraining — мусорка тренера', () => {
  it('возврат тренировки, место свободно, записаться снова нельзя', async () => {
    await seedTraining('t1', hours(1));
    await call('bookTraining', { trainingId: 't1' }, anna);

    const res = await call('removeClientFromTraining', { trainingId: 't1', clientId: anna.uid }, trainer);
    assert.ok(res.result);
    const booking = await read(`trainings/t1/bookings/${anna.uid}`);
    assert.equal(booking.status, 'removed_by_trainer');
    assert.equal(booking.removedBy, trainer.uid);
    assert.equal((await read('trainings/t1')).bookedCount, 0);
    assert.equal((await read('subscriptions/sub_anna')).trainingsLeft, 8);

    assert.equal(reason(await call('bookTraining', { trainingId: 't1' }, anna)), 'removed_by_trainer');
  });

  it('клиент не может удалять других', async () => {
    await seedTraining('t1', hours(24));
    await seedSubscription('sub_olga', olga.uid);
    await call('bookTraining', { trainingId: 't1' }, olga);
    const res = await call('removeClientFromTraining', { trainingId: 't1', clientId: olga.uid }, anna);
    assert.equal(res.error?.status, 'PERMISSION_DENIED');
    assert.equal((await read(`trainings/t1/bookings/${olga.uid}`)).status, 'active');
  });
});

// ============================================================================
describe('createTraining / updateTraining — тренер', () => {
  it('новая тренировка в пустой ячейке; вторая туда же — нельзя', async () => {
    const date = offDay();
    const res = await call('createTraining', {
      date, slot: 'morning', startTime: '09:30', durationMinutes: 45, capacity: 10,
    }, trainer);
    const id = res.result.trainingId;
    const training = await read(`trainings/${id}`);
    assert.equal(training.source, 'manual');
    assert.equal(training.createdBy, trainer.uid);
    assert.equal(training.capacity, 10);
    assert.equal(training.startTime, '09:30');
    const cell = await read(`calendar_slots/${date}_morning`);
    assert.equal(cell.activeTrainingId, id);
    assert.equal(cell.overridesDefault, true);

    const again = await call('createTraining', { date, slot: 'morning' }, trainer);
    assert.equal(reason(again), 'slot_taken');
  });

  it('значения по умолчанию, если тренер их не менял', async () => {
    const res = await call('createTraining', { date: offDay(), slot: 'evening' }, trainer);
    const training = await read(`trainings/${res.result.trainingId}`);
    assert.equal(training.startTime, '18:00');
    assert.equal(training.durationMinutes, 60);
    assert.equal(training.capacity, 13);
  });

  it('в ячейке по расписанию, в прошлом, не в ту строку — нельзя', async () => {
    assert.equal(reason(await call('createTraining', { date: defaultDay(), slot: 'morning' }, trainer)), 'slot_has_default');
    const yesterday = addDays(today(), -1);
    assert.equal(reason(await call('createTraining', { date: yesterday, slot: 'evening' }, trainer)), 'in_past');
    const wrongRow = await call('createTraining', { date: offDay(), slot: 'morning', startTime: '15:00' }, trainer);
    assert.equal(wrongRow.error?.status, 'INVALID_ARGUMENT');
  });

  it('клиент не создаёт и не меняет тренировки; админ — может', async () => {
    assert.equal((await call('createTraining', { date: offDay(), slot: 'morning' }, anna)).error?.status, 'PERMISSION_DENIED');
    await seedTraining('t1', hours(24));
    assert.equal((await call('updateTraining', { trainingId: 't1', capacity: 50 }, anna)).error?.status, 'PERMISSION_DENIED');
    assert.ok((await call('createTraining', { date: offDay(), slot: 'evening' }, admin)).result);
  });

  it('мест не меньше, чем записано — с числом записанных в тексте', async () => {
    await seedTraining('t1', hours(24));
    await seedSubscription('sub_olga', olga.uid);
    await call('bookTraining', { trainingId: 't1' }, anna);
    await call('bookTraining', { trainingId: 't1' }, olga);

    const res = await call('updateTraining', { trainingId: 't1', capacity: 1 }, trainer);
    assert.equal(reason(res), 'capacity_below_booked');
    assert.match(res.error.message, /записано 2/);
    assert.ok((await call('updateTraining', { trainingId: 't1', capacity: 2 }, trainer)).result);
    assert.equal((await read('trainings/t1')).capacity, 2);
  });

  it('смена времени: у записей новое время, уведомление записанным', async () => {
    await seedTraining('t1', hours(48));
    await seedSubscription('sub_olga', olga.uid);
    await call('bookTraining', { trainingId: 't1' }, anna);
    await call('bookTraining', { trainingId: 't1' }, olga);
    await call('cancelBooking', { trainingId: 't1' }, olga);

    const before = await read('trainings/t1');
    const newTime = before.slot === 'morning' ? '07:00' : '20:30';
    const res = await call('updateTraining', { trainingId: 't1', startTime: newTime, durationMinutes: 90 }, trainer);
    // Уведомление — только тем, кто записан сейчас (Ольга отменила).
    assert.deepEqual(res.result, { trainingId: 't1', notifiedClients: 1 });

    const after = await read('trainings/t1');
    assert.equal(after.startTime, newTime);
    assert.equal(after.durationMinutes, 90);
    assert.equal(after.updatedBy, trainer.uid);
    assert.equal(
      (await read(`trainings/t1/bookings/${anna.uid}`)).trainingStartAt.toMillis(),
      after.startAt.toMillis(),
    );
    assert.equal(
      (await read(`trainings/t1/bookings/${olga.uid}`)).trainingStartAt.toMillis(),
      after.startAt.toMillis(),
    );
  });

  it('только места — уведомлений нет', async () => {
    await seedTraining('t1', hours(24));
    await call('bookTraining', { trainingId: 't1' }, anna);
    const res = await call('updateTraining', { trainingId: 't1', capacity: 20 }, trainer);
    assert.equal(res.result.notifiedClients, 0);
  });

  it('правка тренировки по расписанию создаёт её документ', async () => {
    const date = defaultDay();
    const res = await call('updateTraining', { date, slot: 'morning', capacity: 15 }, trainer);
    const training = await read(`trainings/${res.result.trainingId}`);
    assert.equal(training.capacity, 15);
    assert.equal(training.startTime, '08:10');
    assert.equal(training.updatedBy, trainer.uid);
  });

  it('началась — менять нельзя; нечего менять — отказ', async () => {
    await seedTraining('now', -hours(0.2));
    assert.equal(reason(await call('updateTraining', { trainingId: 'now', capacity: 20 }, trainer)), 'training_started');
    await seedTraining('t1', hours(24));
    assert.equal((await call('updateTraining', { trainingId: 't1' }, trainer)).error?.status, 'INVALID_ARGUMENT');
  });
});

// ============================================================================
describe('cancelTraining — отмена тренировки тренером', () => {
  it('всем записанным — возврат; для тренера ячейка снова пустая', async () => {
    const id = await seedTraining('t1', hours(1));
    await seedSubscription('sub_olga', olga.uid, { trainingsLeft: 3 });
    await call('bookTraining', { trainingId: id }, anna);
    await call('bookTraining', { trainingId: id }, olga);

    const res = await call('cancelTraining', { trainingId: id }, trainer);
    assert.deepEqual(res.result, { trainingId: id, refundedClients: 2 });

    const training = await read(`trainings/${id}`);
    assert.equal(training.status, 'cancelled');
    assert.equal(training.cancelledBy, trainer.uid);
    assert.equal(training.bookedCount, 0);
    for (const u of [anna, olga]) {
      assert.equal((await read(`trainings/${id}/bookings/${u.uid}`)).status, 'training_cancelled');
    }
    assert.equal((await read('subscriptions/sub_anna')).trainingsLeft, 8);
    assert.equal((await read('subscriptions/sub_olga')).trainingsLeft, 3);

    const cell = await read(`calendar_slots/${training.slotKey}`);
    assert.equal(cell.activeTrainingId, null);
    assert.equal(cell.overridesDefault, true);

    // Тренер может сразу поставить новую тренировку в ту же ячейку.
    const again = await call('createTraining', { date: training.date, slot: training.slot, startTime: training.startTime }, trainer);
    assert.ok(again.result, JSON.stringify(again));

    // Повторная отмена — отказ.
    assert.equal(reason(await call('cancelTraining', { trainingId: id }, trainer)), 'already_cancelled');
  });

  it('тренировка по расписанию без записей: отменяется только ячейка', async () => {
    const date = defaultDay();
    const res = await call('cancelTraining', { date, slot: 'morning' }, trainer);
    assert.deepEqual(res.result, { trainingId: null, refundedClients: 0 });
    const cell = await read(`calendar_slots/${date}_morning`);
    assert.equal(cell.activeTrainingId, null);
    assert.equal(cell.overridesDefault, true);
    // Тренировка по расписанию не «воскресает».
    assert.equal(reason(await call('bookTraining', { date, slot: 'morning' }, anna)), 'no_training');
  });

  it('клиент отменить тренировку не может', async () => {
    await seedTraining('t1', hours(24));
    assert.equal((await call('cancelTraining', { trainingId: 't1' }, anna)).error?.status, 'PERMISSION_DENIED');
    assert.equal((await read('trainings/t1')).status, 'scheduled');
  });
});

// ============================================================================
describe('freezeSubscription — заморозка', () => {
  it('в пределах лимита: с сегодня, срок сдвигается на число дней', async () => {
    const before = await read('subscriptions/sub_anna');
    const res = await call('freezeSubscription', { days: 2 }, anna);
    assert.deepEqual(res.result.freeze, { startDate: today(), endDate: addDays(today(), 1), days: 2 });

    const sub = await read('subscriptions/sub_anna');
    assert.equal(sub.endDate, addDays(before.endDate, 2));
    assert.equal(sub.originalEndDate, before.originalEndDate);
    assert.equal(sub.freeze.days, 2);

    // Во время заморозки записаться нельзя.
    await seedTraining('t1', hours(24));
    assert.equal(reason(await call('bookTraining', { trainingId: 't1' }, anna)), 'frozen');
  });

  it('один раз за период, даже частично использованная', async () => {
    await call('freezeSubscription', { days: 1 }, anna);
    assert.equal(reason(await call('freezeSubscription', { days: 1 }, anna)), 'freeze_used');
  });

  it('не больше лимита тренера; лимит 0 — заморозки нет', async () => {
    assert.equal(reason(await call('freezeSubscription', { days: 4 }, anna)), 'freeze_limit');
    await seedSubscription('sub_anna', anna.uid, { freezeLimitDays: 0 });
    assert.equal(reason(await call('freezeSubscription', { days: 1 }, anna)), 'freeze_unavailable');
  });

  it('без абонемента или с истёкшим — нельзя; кривое число дней — отказ', async () => {
    assert.equal(reason(await call('freezeSubscription', { days: 1 }, olga)), 'no_subscription');
    await seedSubscription('sub_anna', anna.uid, { endDate: addDays(today(), -1) });
    assert.equal(reason(await call('freezeSubscription', { days: 1 }, anna)), 'subscription_inactive');
    for (const days of [0, -1, 1.5, '2']) {
      assert.equal((await call('freezeSubscription', { days }, anna)).error?.status, 'INVALID_ARGUMENT');
    }
  });
});

// ============================================================================
describe('renewSubscription — продление тренером', () => {
  it('новая запись, старая в истории, заморозка снова доступна', async () => {
    await call('freezeSubscription', { days: 1 }, anna);
    const res = await call('renewSubscription', {
      clientId: anna.uid,
      startDate: today(),
      endDate: addDays(today(), 29),
      trainings: 12,
      freezeLimitDays: 5,
    }, trainer);
    const id = res.result.subscriptionId;
    assert.equal(res.result.previousSubscriptionId, 'sub_anna');

    const old = await read('subscriptions/sub_anna');
    assert.equal(old.isCurrent, false);
    assert.ok(old.closedAt instanceof Timestamp);
    assert.equal(old.trainingsLeft, 8, 'история не меняется');

    const sub = await read(`subscriptions/${id}`);
    assert.equal(sub.isCurrent, true);
    assert.equal(sub.clientId, anna.uid);
    assert.equal(sub.trainingsTotal, 12);
    assert.equal(sub.trainingsLeft, 12);
    assert.equal(sub.freezeLimitDays, 5);
    assert.equal(sub.freeze, null);
    assert.equal(sub.createdBy, trainer.uid);
    assert.equal((await read(`users/${anna.uid}`)).currentSubscriptionId, id);

    assert.ok((await call('freezeSubscription', { days: 5 }, anna)).result);
  });

  it('первый абонемент клиенту без абонемента', async () => {
    const res = await call('renewSubscription', {
      clientId: olga.uid, startDate: today(), endDate: addDays(today(), 29), trainings: 11, freezeLimitDays: 3,
    }, trainer);
    assert.equal(res.result.previousSubscriptionId, null);
    assert.equal((await readAll('subscriptions')).filter((s) => s.clientId === olga.uid).length, 1);
  });

  it('клиент себе продлить не может; тренеру абонемент не оформляется; кривые даты — отказ', async () => {
    const args = { clientId: anna.uid, startDate: today(), endDate: addDays(today(), 29), trainings: 99, freezeLimitDays: 3 };
    assert.equal((await call('renewSubscription', args, anna)).error?.status, 'PERMISSION_DENIED');
    assert.equal(reason(await call('renewSubscription', { ...args, clientId: trainer.uid }, trainer)), 'not_client');
    assert.equal((await call('renewSubscription', { ...args, endDate: addDays(today(), -5) }, trainer)).error?.status, 'INVALID_ARGUMENT');
    assert.equal(
      reason(await call('renewSubscription', { ...args, startDate: addDays(today(), -40), endDate: addDays(today(), -10) }, trainer)),
      'ends_in_past',
    );
    assert.equal((await call('renewSubscription', { ...args, trainings: 0 }, trainer)).error?.status, 'INVALID_ARGUMENT');
    assert.equal((await read('subscriptions/sub_anna')).isCurrent, true);
  });
});

// ============================================================================
describe('сгорание тренировок по сроку', () => {
  it('истёкший: тренировки сгорают, отметка времени; действующий не трогается; повтор — без изменений', async () => {
    await seedSubscription('sub_olga', olga.uid, {
      startDate: addDays(today(), -31),
      endDate: addDays(today(), -1),
      trainingsLeft: 5,
    });
    await seedSubscription('sub_ira', ira.uid, {
      startDate: addDays(today(), -40),
      endDate: addDays(today(), -10),
      trainingsLeft: 0,
    });

    const res = await call('runSubscriptionExpiry', {}, admin);
    assert.deepEqual(res.result, { expired: 2, burned: 5, reminded: 0 });

    const olgaSub = await read('subscriptions/sub_olga');
    assert.equal(olgaSub.trainingsLeft, 0);
    assert.equal(olgaSub.burnedTrainings, 5);
    assert.ok(olgaSub.expiredAt instanceof Timestamp);
    assert.equal(olgaSub.notified.expired, true);
    assert.equal((await read('subscriptions/sub_anna')).trainingsLeft, 8);

    assert.deepEqual((await call('runSubscriptionExpiry', {}, admin)).result, { expired: 0, burned: 0, reminded: 0 });
  });

  it('последний день абонемента — сегодня: ещё действует', async () => {
    await seedSubscription('sub_anna', anna.uid, { endDate: today() });
    await call('runSubscriptionExpiry', {}, admin);
    assert.equal((await read('subscriptions/sub_anna')).trainingsLeft, 8);
  });

  it('возврат тренировки в истёкший абонемент уходит в сгоревшие', async () => {
    await seedTraining('t1', hours(24));
    await call('bookTraining', { trainingId: 't1' }, anna);
    // Срок истёк, а продления ещё не было.
    const sub = await read('subscriptions/sub_anna');
    await seed('subscriptions/sub_anna', { ...sub, endDate: addDays(today(), -1), trainingsLeft: 0, burnedTrainings: 7 });
    await call('cancelTraining', { trainingId: 't1' }, trainer);
    const after = await read('subscriptions/sub_anna');
    assert.equal(after.trainingsLeft, 0);
    assert.equal(after.burnedTrainings, 8);
  });

  it('запуск вручную — только администратору', async () => {
    assert.equal((await call('runSubscriptionExpiry', {}, trainer)).error?.status, 'PERMISSION_DENIED');
  });
});

// Пустая проверка вспомогательной логики дней недели — чтобы расчёты
// тестов совпадали с функциями (1 = понедельник).
it('isoWeekday: 2026-09-28 — понедельник', () => {
  assert.equal(isoWeekday('2026-09-28'), 1);
});
