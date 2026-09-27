import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { argsOf, day, optionalInt, optionalTime, slot as slotArg, trainingTarget } from './args.js';
import { refuse, requireStaff } from './auth.js';
import { TrainingDoc, hasStarted, materialize, resolveTraining, slotRef } from './calendar.js';
import { Collections, Limits, REGION } from './config.js';
import { notifyAfterCommit } from './notifications.js';
import { RefundPlan, applyRefund, planRefund } from './refunds.js';
import { loadSettings } from './settings.js';
import { DaySlot, isoWeekday, ruDate, slotKeyOf, slotOfTime, studioDay, studioInstant } from './time.js';

/**
 * Календарь глазами тренера (ТЗ 3.2). Календарь общий: любой тренер или
 * админ меняет любую тренировку, кто бы её ни создал (ТЗ 1).
 */

const db = () => getFirestore();

const SLOT_LABEL: Record<DaySlot, string> = { morning: 'утро', evening: 'вечер' };

function requireTimeFitsSlot(startTime: string, slot: DaySlot): void {
  if (slotOfTime(startTime) !== slot) {
    throw new HttpsError(
      'invalid-argument',
      `Время ${startTime} не подходит для строки «${SLOT_LABEL[slot]}»: утро — до 14:00, вечер — с 14:00.`,
    );
  }
}

/**
 * Назначить тренировку в пустую ячейку («+», ТЗ 3.2).
 *
 * Аргументы: `{ date, slot, startTime?, durationMinutes?, capacity? }` —
 * не переданные значения берутся из settings/defaults (ТЗ 7).
 * В ячейке не может быть двух активных тренировок: проверка и запись
 * ячейки — в одной транзакции. Если в ячейке тренировка по расписанию,
 * новую не создаём — её нужно изменить (updateTraining).
 */
export const createTraining = onCall({ region: REGION }, async (request) => {
  const caller = await requireStaff(request);
  const args = argsOf(request.data);
  const settings = await loadSettings();

  const date = day(args, 'date', 'Дата');
  const slot = slotArg(args);
  const startTime =
    optionalTime(args, 'startTime') ?? (slot === 'morning' ? settings.morningTime : settings.eveningTime);
  const durationMinutes =
    optionalInt(args, 'durationMinutes', 'Длительность', Limits.durationMinutes) ?? settings.durationMinutes;
  const capacity = optionalInt(args, 'capacity', 'Количество мест', Limits.capacity) ?? settings.capacity;
  requireTimeFitsSlot(startTime, slot);

  const startAt = studioInstant(date, startTime);
  if (startAt.getTime() <= Date.now()) {
    refuse('in_past', 'Нельзя назначить тренировку на прошедшее время.');
  }

  const key = slotKeyOf(date, slot);
  const ref = db().collection(Collections.trainings).doc();

  await db().runTransaction(async (tx) => {
    const cell = await tx.get(slotRef(key));
    if (cell.exists && typeof cell.get('activeTrainingId') === 'string') {
      refuse('slot_taken', 'В этой ячейке уже есть тренировка.');
    }
    if (!cell.exists && settings.weekdays.includes(isoWeekday(date))) {
      refuse(
        'slot_has_default',
        'В этой ячейке тренировка по расписанию — измените её, а не создавайте новую.',
      );
    }

    tx.set(ref, {
      slotKey: key,
      date,
      slot,
      startTime,
      startAt: Timestamp.fromDate(startAt),
      durationMinutes,
      capacity,
      bookedCount: 0,
      status: 'scheduled',
      source: 'manual',
      createdAt: FieldValue.serverTimestamp(),
      createdBy: caller.uid,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: caller.uid,
    });
    tx.set(slotRef(key), {
      date,
      slot,
      activeTrainingId: ref.id,
      overridesDefault: true,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  logger.info('Тренировка назначена', { trainingId: ref.id, date, slot, by: caller.uid });
  return { trainingId: ref.id };
});

/**
 * Изменить тренировку: время, длительность, количество мест (ТЗ 3.2).
 *
 * Аргументы: `{ trainingId }` или `{ date, slot }` (тренировка по расписанию)
 * и хотя бы одно из `startTime`, `durationMinutes`, `capacity`.
 * - Мест нельзя сделать меньше, чем уже записано (reason
 *   `capacity_below_booked`, в тексте — сколько записано).
 * - Время остаётся в своей строке сетки (утро до 14:00, вечер с 14:00).
 * - Начавшуюся или отменённую тренировку менять нельзя.
 * При смене времени у всех записей обновляется `trainingStartAt`.
 * Если изменились время или длительность, всем записанным (active) уходит
 * уведомление; их число возвращается в `notifiedClients`.
 */
export const updateTraining = onCall({ region: REGION }, async (request) => {
  const caller = await requireStaff(request);
  const args = argsOf(request.data);
  const target = trainingTarget(args);
  const newTime = optionalTime(args, 'startTime');
  const newDuration = optionalInt(args, 'durationMinutes', 'Длительность', Limits.durationMinutes);
  const newCapacity = optionalInt(args, 'capacity', 'Количество мест', Limits.capacity);
  if (newTime === undefined && newDuration === undefined && newCapacity === undefined) {
    throw new HttpsError('invalid-argument', 'Нечего менять.');
  }
  const settings = await loadSettings();

  const result = await db().runTransaction(async (tx) => {
    const now = new Date();
    const training = await resolveTraining(tx, target, settings);
    if (!training) refuse('no_training', 'В этой ячейке нет тренировки.');
    const t = training.data;
    if (t.status !== 'scheduled') refuse('training_cancelled', 'Тренировка отменена.');
    if (hasStarted(t, now)) refuse('training_started', 'Тренировка уже началась — изменить её нельзя.');

    const startTime = newTime ?? t.startTime;
    const durationMinutes = newDuration ?? t.durationMinutes;
    const capacity = newCapacity ?? t.capacity;
    requireTimeFitsSlot(startTime, t.slot);

    if (capacity < t.bookedCount) {
      refuse(
        'capacity_below_booked',
        `Нельзя поставить меньше мест, чем уже записано: записано ${t.bookedCount}.`,
      );
    }
    const startAt = Timestamp.fromDate(studioInstant(t.date, startTime));
    const timeChanged = startTime !== t.startTime;
    if (timeChanged && startAt.toMillis() <= now.getTime()) {
      refuse('in_past', 'Нельзя перенести тренировку на прошедшее время.');
    }
    const scheduleChanged = timeChanged || durationMinutes !== t.durationMinutes;

    // Записи читаем, только если меняется расписание (обновить время / уведомить).
    const bookings =
      scheduleChanged && !training.virtual
        ? (await tx.get(training.ref.collection(Collections.bookings))).docs
        : [];

    const updated: TrainingDoc = { ...t, startTime, startAt, durationMinutes, capacity };
    if (training.virtual) {
      materialize(tx, training, updated, caller.uid);
    } else {
      tx.update(training.ref, {
        startTime,
        startAt,
        durationMinutes,
        capacity,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: caller.uid,
      });
    }
    if (timeChanged) {
      for (const booking of bookings) tx.update(booking.ref, { trainingStartAt: startAt });
    }

    const recipients = scheduleChanged
      ? bookings.filter((b) => b.get('status') === 'active').map((b) => b.id)
      : [];
    return {
      trainingId: training.ref.id,
      date: t.date,
      slot: t.slot,
      startTime,
      durationMinutes,
      recipients,
    };
  });

  logger.info('Тренировка изменена', { trainingId: result.trainingId, by: caller.uid });
  await notifyAfterCommit(result.recipients, {
    kind: 'training_changed',
    title: 'Тренировка изменена',
    body:
      `Тренировка ${ruDate(result.date)} теперь начинается в ${result.startTime} ` +
      `и длится ${result.durationMinutes} мин. Ваша запись сохранена.`,
    data: { trainingId: result.trainingId, date: result.date, slot: result.slot },
  });
  return { trainingId: result.trainingId, notifiedClients: result.recipients.length };
});

/**
 * Отменить тренировку (ТЗ 3.2): всем записанным тренировка возвращается
 * на абонемент, им уходит уведомление.
 *
 * Аргументы: `{ trainingId }` или `{ date, slot }`.
 *
 * КАК ЭТО ВЫГЛЯДИТ В КАЛЕНДАРЕ (для экранов на этапах 5–6):
 * - Документ тренировки остаётся со `status: 'cancelled'` — это история.
 * - Ячейка calendar_slots получает `activeTrainingId: null` и
 *   `overridesDefault: true`. Для ТРЕНЕРА ячейка поэтому ПУСТАЯ («+»):
 *   можно сразу назначить новую тренировку (createTraining), а тренировка
 *   по расписанию в этот день больше не «воскресает».
 * - Для КЛИЕНТА, который был записан, его запись получает статус
 *   `training_cancelled`. Приложение показывает «Отменено» там, где ячейка
 *   пуста (или в ней уже новая тренировка — тогда показывается она), а у
 *   клиента есть запись training_cancelled на этот день и строку.
 *   Клиенты, которые не были записаны, видят обычную пустую ячейку.
 * Отменить тренировку по расписанию, которой ещё нет в базе, можно:
 * тогда меняется только ячейка — записей у такой тренировки нет.
 */
export const cancelTraining = onCall({ region: REGION }, async (request) => {
  const caller = await requireStaff(request);
  const target = trainingTarget(argsOf(request.data));
  const settings = await loadSettings();

  const result = await db().runTransaction(async (tx) => {
    const now = new Date();
    const today = studioDay(now);

    // --- чтение
    const training = await resolveTraining(tx, target, settings);
    if (!training) refuse('no_training', 'В этой ячейке нет тренировки.');
    const t = training.data;
    if (t.status !== 'scheduled') refuse('already_cancelled', 'Тренировка уже отменена.');
    if (hasStarted(t, now)) refuse('training_started', 'Тренировка уже началась — отменить её нельзя.');

    const cellUpdate = {
      date: t.date,
      slot: t.slot,
      activeTrainingId: null,
      overridesDefault: true,
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (training.virtual) {
      // Документа тренировки ещё нет, записей тоже — отменяем только ячейку.
      tx.set(training.slotRef, cellUpdate);
      return {
        trainingId: null,
        date: t.date,
        slot: t.slot,
        startTime: t.startTime,
        recipients: [] as string[],
      };
    }

    const cell = await tx.get(training.slotRef);
    const active = (
      await tx.get(training.ref.collection(Collections.bookings).where('status', '==', 'active'))
    ).docs;
    const refunds: (RefundPlan | null)[] = [];
    for (const booking of active) {
      refunds.push(
        await planRefund(
          tx,
          { clientId: booking.id, subscriptionId: String(booking.get('subscriptionId')) },
          today,
        ),
      );
    }

    // --- запись
    tx.update(training.ref, {
      status: 'cancelled',
      bookedCount: 0,
      cancelledAt: FieldValue.serverTimestamp(),
      cancelledBy: caller.uid,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: caller.uid,
    });
    for (const booking of active) {
      tx.update(booking.ref, {
        status: 'training_cancelled',
        cancelledAt: FieldValue.serverTimestamp(),
      });
    }
    for (const refund of refunds) if (refund) applyRefund(tx, refund);
    if (!cell.exists || cell.get('activeTrainingId') === training.ref.id) {
      tx.set(training.slotRef, cellUpdate);
    }

    return {
      trainingId: training.ref.id,
      date: t.date,
      slot: t.slot,
      startTime: t.startTime,
      recipients: active.map((b) => b.id),
    };
  });

  logger.info('Тренировка отменена', { trainingId: result.trainingId, by: caller.uid });
  await notifyAfterCommit(result.recipients, {
    kind: 'training_cancelled',
    title: 'Тренировка отменена',
    body:
      `Тренировка ${ruDate(result.date)} в ${result.startTime} отменена. ` +
      'Тренировка вернулась на абонемент.',
    data: {
      ...(result.trainingId ? { trainingId: result.trainingId } : {}),
      date: result.date,
      slot: result.slot,
    },
  });
  return { trainingId: result.trainingId, refundedClients: result.recipients.length };
});
