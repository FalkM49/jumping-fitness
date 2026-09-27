// Уведомления (этап 7): каждое событие из ТЗ оставляет запись в истории
// users/{uid}/notifications — второй канал рядом с push (push в эмуляторе
// не отправляется, у него нет FCM).

import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  Timestamp,
  addDays,
  call,
  clearDb,
  hours,
  profile,
  readAll,
  seed,
  seedSubscription,
  seedTraining,
  signUp,
  startEnv,
  stopEnv,
  today,
} from './helpers.mjs';

let anna, olga, trainer, admin;

before(async () => {
  await startEnv();
  [anna, olga, trainer, admin] = await Promise.all([signUp(), signUp(), signUp(), signUp()]);
});
after(stopEnv);

beforeEach(async () => {
  await clearDb();
  await seed(`users/${anna.uid}`, profile('Анна Смирнова'));
  await seed(`users/${olga.uid}`, profile('Ольга Петрова'));
  await seed(`users/${trainer.uid}`, profile('Мария Ковалёва', 'trainer'));
  await seed(`users/${admin.uid}`, profile('Разработчик', 'client', { isAdmin: true }));
  await seedSubscription('sub_anna', anna.uid);
});

const inbox = (user) => readAll(`users/${user.uid}/notifications`);

/** Триггеры Firestore срабатывают асинхронно — ждём появления записи. */
async function waitForInbox(user, count = 1) {
  for (let i = 0; i < 40; i++) {
    const items = await inbox(user);
    if (items.length >= count) return items;
    await new Promise((r) => setTimeout(r, 250));
  }
  return inbox(user);
}

describe('уведомления клиенту о тренировке', () => {
  it('изменение времени — с датой и строкой для перехода', async () => {
    await seedTraining('t1', hours(48));
    await call('bookTraining', { trainingId: 't1' }, anna);
    const training = (await readAll('trainings')).find((t) => t.id === 't1');
    const newTime = training.slot === 'morning' ? '07:00' : '20:30';
    await call('updateTraining', { trainingId: 't1', startTime: newTime }, trainer);

    const [n] = await inbox(anna);
    assert.equal(n.kind, 'training_changed');
    assert.equal(n.read, false);
    assert.ok(n.createdAt instanceof Timestamp);
    assert.match(n.body, new RegExp(newTime));
    assert.deepEqual(
      { kind: n.data.kind, trainingId: n.data.trainingId, date: n.data.date, slot: n.data.slot },
      { kind: 'training_changed', trainingId: 't1', date: training.date, slot: training.slot },
    );
  });

  it('отмена тренировки и удаление с тренировки', async () => {
    await seedTraining('t1', hours(24));
    await seedTraining('t2', hours(50));
    await call('bookTraining', { trainingId: 't1' }, anna);
    await call('bookTraining', { trainingId: 't2' }, anna);
    await call('cancelTraining', { trainingId: 't1' }, trainer);
    await call('removeClientFromTraining', { trainingId: 't2', clientId: anna.uid }, trainer);

    const kinds = (await inbox(anna)).map((n) => n.kind).sort();
    assert.deepEqual(kinds, ['removed_from_training', 'training_cancelled']);
  });
});

describe('уведомления об абонементе', () => {
  it('осталась 1 тренировка — один раз за период', async () => {
    await seedSubscription('sub_anna', anna.uid, { trainingsLeft: 2 });
    await seedTraining('t1', hours(24));
    await seedTraining('t2', hours(26));
    await call('bookTraining', { trainingId: 't1' }, anna); // осталось 1
    await call('cancelBooking', { trainingId: 't1' }, anna); // снова 2
    await call('bookTraining', { trainingId: 't1' }, anna); // снова 1 — без повтора
    await call('bookTraining', { trainingId: 't2' }, anna); // 0 — флаг уже стоит

    const low = (await inbox(anna)).filter((n) => n.kind === 'subscription_low_trainings');
    assert.equal(low.length, 1);
    assert.match(low[0].body, /осталась 1 тренировка/);
  });

  it('скоро закончится и истёк — из ежедневной проверки', async () => {
    await seedSubscription('sub_anna', anna.uid, { endDate: addDays(today(), 3) });
    await seedSubscription('sub_olga', olga.uid, {
      startDate: addDays(today(), -31),
      endDate: addDays(today(), -1),
      trainingsLeft: 4,
    });

    const res = await call('runSubscriptionExpiry', {}, admin);
    assert.deepEqual(res.result, { expired: 1, burned: 4, reminded: 1 });
    // Повторный запуск — без повторных напоминаний.
    assert.equal((await call('runSubscriptionExpiry', {}, admin)).result.reminded, 0);

    const annaInbox = await inbox(anna);
    assert.deepEqual(annaInbox.map((n) => n.kind), ['subscription_ending_soon']);
    assert.match(annaInbox[0].body, /осталось 4 дн/);

    const olgaInbox = await inbox(olga);
    assert.deepEqual(olgaInbox.map((n) => n.kind), ['subscription_expired']);
    assert.match(olgaInbox[0].body, /сгорели/);
  });
});

describe('заявки в тренеры', () => {
  it('новая заявка — администратору, решение — заявителю', async () => {
    await seed(`trainer_requests/${olga.uid}`, {
      uid: olga.uid,
      fullName: 'Ольга Петрова',
      phone: '+79990000000',
      status: 'pending',
      createdAt: Timestamp.now(),
    });
    // Приложение сообщает о заявке само (в Yandex Cloud триггеров нет);
    // в Firebase сработает и триггер — администратор всё равно получит одно.
    await call('notifyTrainerRequest', {}, olga);
    const [forAdmin] = await waitForInbox(admin);
    assert.equal(forAdmin?.kind, 'trainer_request_new');
    assert.match(forAdmin.body, /Ольга Петрова/);
    assert.equal((await inbox(trainer)).length, 0, 'обычному тренеру — нет');

    const again = await call('notifyTrainerRequest', {}, olga);
    assert.deepEqual(again.result, { notified: false });
    await new Promise((resolve) => setTimeout(resolve, 1500));
    assert.equal((await inbox(admin)).length, 1, 'администратору — ровно одно');

    await call('rejectTrainerRequest', { uid: olga.uid }, admin);
    const [forOlga] = await inbox(olga);
    assert.equal(forOlga.kind, 'trainer_request_rejected');
  });
});
