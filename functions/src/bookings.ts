import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { argsOf, docId, trainingTarget } from './args.js';
import { refuse, requireStaff, requireUser } from './auth.js';
import { hasStarted, materialize, resolveTraining, trainingRef } from './calendar.js';
import { Collections, REGION } from './config.js';
import { notifyAfterCommit } from './notifications.js';
import { applyRefund, planRefund } from './refunds.js';
import { loadSettings } from './settings.js';
import { isWithin, ruDate, studioDay } from './time.js';

/**
 * Запись клиентов на тренировки (ТЗ 3.1, 3.2, 8).
 *
 * Запись лежит в trainings/{id}/bookings/{uid клиента}: второй записи того
 * же клиента на ту же тренировку быть не может физически. Места, счёт
 * тренировок и статус записи меняются одной транзакцией — одновременные
 * нажатия двух клиентов на последнее место не дадут 14/13.
 */

export type BookingStatus =
  | 'active'
  | 'cancelled_by_client'
  | 'removed_by_trainer'
  | 'training_cancelled';

const db = () => getFirestore();
const userRef = (uid: string) => db().collection(Collections.users).doc(uid);
const subscriptionRef = (id: string) => db().collection(Collections.subscriptions).doc(id);

/**
 * Записаться на тренировку.
 *
 * Аргументы: `{ trainingId }` или `{ date, slot }` (тренировка по расписанию,
 * которой ещё нет в базе). Условия (ТЗ 3.1) — все по серверному времени:
 * абонемент текущий и действует сегодня, тренировка в пределах его срока,
 * не идёт заморозка, есть тренировки на счету, есть свободное место,
 * тренировка ещё не началась и не отменена, тренер не удалял клиента
 * с этой тренировки. При отказе — failed-precondition с `details.reason`.
 *
 * Итог: запись active, на тренировке +1 место, на абонементе −1 тренировка.
 */
export const bookTraining = onCall({ region: REGION }, async (request) => {
  const caller = await requireUser(request);
  if (caller.role === 'trainer') {
    refuse('trainer_cannot_book', 'Тренер не записывается на тренировки.');
  }
  const target = trainingTarget(argsOf(request.data));
  const settings = await loadSettings();

  const result = await db().runTransaction(async (tx) => {
    const now = new Date();
    const today = studioDay(now);

    // --- чтение
    const training = await resolveTraining(tx, target, settings);
    if (!training) refuse('no_training', 'В этой ячейке нет тренировки.');
    const bookingRef = training.ref.collection(Collections.bookings).doc(caller.uid);
    const [booking, user] = await Promise.all([tx.get(bookingRef), tx.get(userRef(caller.uid))]);
    const subscriptionId = user.get('currentSubscriptionId');
    const subscription =
      typeof subscriptionId === 'string' ? await tx.get(subscriptionRef(subscriptionId)) : null;

    // --- проверки
    const t = training.data;
    if (t.status !== 'scheduled') refuse('training_cancelled', 'Тренировка отменена.');
    if (hasStarted(t, now)) refuse('training_started', 'Тренировка уже началась.');

    const previous = booking.exists ? (booking.get('status') as BookingStatus) : null;
    if (previous === 'active') refuse('already_booked', 'Вы уже записаны на эту тренировку.');
    if (previous === 'removed_by_trainer') {
      refuse(
        'removed_by_trainer',
        'Тренер отменил вашу запись на эту тренировку — записаться на неё снова нельзя.',
      );
    }

    if (
      !subscription?.exists ||
      subscription.get('isCurrent') !== true ||
      subscription.get('clientId') !== caller.uid
    ) {
      refuse('no_subscription', 'Нет действующего абонемента. Оформите его у тренера.');
    }
    const startDate = String(subscription.get('startDate'));
    const endDate = String(subscription.get('endDate'));
    const trainingsLeft = Number(subscription.get('trainingsLeft') ?? 0);
    const freeze = subscription.get('freeze') as { startDate: string; endDate: string } | null;

    if (today < startDate) {
      refuse('subscription_not_started', `Абонемент начнёт действовать ${ruDate(startDate)}.`);
    }
    if (today > endDate) {
      refuse('subscription_expired', 'Срок абонемента истёк. Продлите его у тренера.');
    }
    if (!isWithin(t.date, startDate, endDate)) {
      refuse(
        'outside_subscription',
        `Абонемент действует по ${ruDate(endDate)} — на более позднюю тренировку записаться нельзя.`,
      );
    }
    if (freeze && isWithin(today, freeze.startDate, freeze.endDate)) {
      refuse('frozen', `Идёт заморозка абонемента до ${ruDate(freeze.endDate)} включительно.`);
    }
    if (trainingsLeft <= 0) {
      refuse('no_trainings_left', 'На абонементе не осталось тренировок. Продлите его у тренера.');
    }
    if (t.bookedCount >= t.capacity) refuse('full', 'Свободных мест нет.');

    // --- запись
    const bookedCount = t.bookedCount + 1;
    if (training.virtual) {
      materialize(tx, training, { ...t, bookedCount });
    } else {
      tx.update(training.ref, { bookedCount });
    }
    tx.set(bookingRef, {
      clientId: caller.uid,
      clientName: caller.fullName,
      trainingId: training.ref.id,
      trainingStartAt: t.startAt,
      status: 'active' satisfies BookingStatus,
      subscriptionId: subscription.id,
      bookedAt: FieldValue.serverTimestamp(),
      cancelledAt: null,
    });
    // Тренировок осталось мало (ТЗ 5 п. 2) — предупредить один раз за период.
    const left = trainingsLeft - 1;
    const warnLow =
      left <= settings.lowTrainingsThreshold && subscription.get('notified.lowTrainings') !== true;
    tx.update(subscription.ref, {
      trainingsLeft: left,
      ...(warnLow ? { 'notified.lowTrainings': true } : {}),
    });

    return { trainingId: training.ref.id, bookedCount, trainingsLeft: left, warnLow };
  });

  logger.info('Запись на тренировку', { uid: caller.uid, trainingId: result.trainingId });
  if (result.warnLow) {
    const left = result.trainingsLeft;
    await notifyAfterCommit([caller.uid], {
      kind: 'subscription_low_trainings',
      title: left === 0 ? 'Тренировки закончились' : 'Абонемент заканчивается',
      body:
        left === 0
          ? 'На абонементе не осталось тренировок. Продлите абонемент у тренера.'
          : `На абонементе ${left === 1 ? 'осталась 1 тренировка' : `осталось тренировок: ${left}`}. ` +
            'Не забудьте продлить абонемент у тренера.',
    });
  }
  return {
    trainingId: result.trainingId,
    bookedCount: result.bookedCount,
    trainingsLeft: result.trainingsLeft,
  };
});

/**
 * Отменить свою запись. Доступно, только если до начала строго больше
 * `cancelWindowHours` (3 ч, ТЗ 3.1) по серверному времени: ровно за 3 часа
 * и позже — отказ `cancel_window_passed`. Тренировка возвращается на
 * абонемент, место освобождается; записаться снова можно.
 */
export const cancelBooking = onCall({ region: REGION }, async (request) => {
  const caller = await requireUser(request);
  const trainingId = docId(argsOf(request.data), 'trainingId', 'тренировка');
  const settings = await loadSettings();

  return db().runTransaction(async (tx) => {
    const now = new Date();
    const ref = trainingRef(trainingId);
    const bookingRef = ref.collection(Collections.bookings).doc(caller.uid);
    const [training, booking] = await Promise.all([tx.get(ref), tx.get(bookingRef)]);
    if (!training.exists) throw new HttpsError('not-found', 'Тренировка не найдена.');
    if (!booking.exists || booking.get('status') !== 'active') {
      refuse('not_booked', 'Вы не записаны на эту тренировку.');
    }

    const windowMs = settings.cancelWindowHours * 60 * 60 * 1000;
    const startsInMs = training.get('startAt').toMillis() - now.getTime();
    if (startsInMs <= windowMs) {
      refuse(
        'cancel_window_passed',
        `Отмена уже недоступна: отменить запись можно не позже чем за ${settings.cancelWindowHours} ч до начала.`,
      );
    }

    const refund = await planRefund(
      tx,
      { clientId: caller.uid, subscriptionId: String(booking.get('subscriptionId')) },
      studioDay(now),
    );

    tx.update(bookingRef, {
      status: 'cancelled_by_client' satisfies BookingStatus,
      cancelledAt: FieldValue.serverTimestamp(),
    });
    tx.update(ref, { bookedCount: Math.max(0, Number(training.get('bookedCount')) - 1) });
    if (refund) applyRefund(tx, refund);

    return { trainingId, refunded: refund !== null };
  });
});

/**
 * Тренер удаляет клиента с тренировки (иконка мусорки, ТЗ 3.2): тренировка
 * возвращается на абонемент клиента, место освобождается, запись получает
 * статус removed_by_trainer — записаться именно на эту тренировку клиент
 * больше не сможет (bookTraining откажет с reason `removed_by_trainer`).
 * Клиенту уходит уведомление.
 */
export const removeClientFromTraining = onCall({ region: REGION }, async (request) => {
  const caller = await requireStaff(request);
  const args = argsOf(request.data);
  const trainingId = docId(args, 'trainingId', 'тренировка');
  const clientId = docId(args, 'clientId', 'клиент');

  const removed = await db().runTransaction(async (tx) => {
    const now = new Date();
    const ref = trainingRef(trainingId);
    const bookingRef = ref.collection(Collections.bookings).doc(clientId);
    const [training, booking] = await Promise.all([tx.get(ref), tx.get(bookingRef)]);
    if (!training.exists) throw new HttpsError('not-found', 'Тренировка не найдена.');
    if (!booking.exists || booking.get('status') !== 'active') {
      refuse('not_booked', 'Клиент не записан на эту тренировку.');
    }

    const refund = await planRefund(
      tx,
      { clientId, subscriptionId: String(booking.get('subscriptionId')) },
      studioDay(now),
    );

    tx.update(bookingRef, {
      status: 'removed_by_trainer' satisfies BookingStatus,
      cancelledAt: FieldValue.serverTimestamp(),
      removedBy: caller.uid,
    });
    tx.update(ref, { bookedCount: Math.max(0, Number(training.get('bookedCount')) - 1) });
    if (refund) applyRefund(tx, refund);

    return {
      date: String(training.get('date')),
      slot: String(training.get('slot')),
      startTime: String(training.get('startTime')),
    };
  });

  logger.info('Тренер удалил клиента с тренировки', { trainingId, clientId, by: caller.uid });
  await notifyAfterCommit([clientId], {
    kind: 'removed_from_training',
    title: 'Запись отменена тренером',
    body:
      `Тренер отменил вашу запись на ${ruDate(removed.date)}, ${removed.startTime}. ` +
      'Тренировка вернулась на абонемент.',
    data: { trainingId, date: removed.date, slot: removed.slot },
  });
  return { trainingId, clientId };
});
