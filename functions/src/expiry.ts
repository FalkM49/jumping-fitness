import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { requireAdmin } from './auth.js';
import { Collections, REGION, STUDIO_TIMEZONE } from './config.js';
import { notifyAfterCommit } from './notifications.js';
import { loadSettings } from './settings.js';
import { addDays, daysBetween, ruDate, studioDay } from './time.js';

/**
 * Истечение абонементов по сроку (ТЗ 5 п. 3, ТЗ 8.5).
 *
 * Текущий абонемент, у которого последний день уже прошёл, фиксируется
 * как истёкший: оставшиеся тренировки сгорают (`trainingsLeft → 0`,
 * сколько сгорело — в `burnedTrainings`), ставится `expiredAt`, клиенту
 * уходит уведомление. Работает по расписанию на сервере — не зависит от
 * того, открывал ли клиент приложение. Повторный запуск ничего не меняет:
 * уже истёкшие (с `expiredAt`) пропускаются.
 */
export async function expireSubscriptions(now: Date = new Date()): Promise<{ expired: number; burned: number }> {
  const db = getFirestore();
  const today = studioDay(now);
  // Индекс isCurrent + endDate — firestore.indexes.json.
  const candidates = await db
    .collection(Collections.subscriptions)
    .where('isCurrent', '==', true)
    .where('endDate', '<', today)
    .get();

  let expired = 0;
  let burned = 0;
  for (const doc of candidates.docs) {
    if (doc.get('expiredAt')) continue;

    // Отдельная транзакция на абонемент: одновременное продление или
    // возврат тренировки не потеряются, а сбой одного не остановит остальные.
    const outcome = await db
      .runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        if (snap.get('isCurrent') !== true || snap.get('expiredAt') || !(String(snap.get('endDate')) < today)) {
          return null;
        }
        const left = Math.max(0, Number(snap.get('trainingsLeft') ?? 0));
        tx.update(doc.ref, {
          trainingsLeft: 0,
          burnedTrainings: Number(snap.get('burnedTrainings') ?? 0) + left,
          expiredAt: FieldValue.serverTimestamp(),
          'notified.expired': true,
        });
        return { clientId: String(snap.get('clientId')), burned: left };
      })
      .catch((error: unknown) => {
        logger.error('Не удалось завершить абонемент', { subscriptionId: doc.id, error });
        return null;
      });
    if (!outcome) continue;

    expired++;
    burned += outcome.burned;
    await notifyAfterCommit([outcome.clientId], {
      kind: 'subscription_expired',
      title: 'Срок абонемента истёк',
      body:
        outcome.burned > 0
          ? 'Срок абонемента истёк, оставшиеся тренировки сгорели. Продлите абонемент у тренера.'
          : 'Срок абонемента истёк. Продлите абонемент у тренера.',
      data: { subscriptionId: doc.id },
    });
  }

  logger.info('Проверка сроков абонементов', { today, expired, burned });
  return { expired, burned };
}

/**
 * «Абонемент скоро закончится» (ТЗ 5 п. 1): текущим абонементам, у которых
 * осталось `endingSoonDays` дней или меньше (включая сегодняшний), — одно
 * уведомление за период. Флаг `notified.endingSoon` сбрасывает заморозка
 * (срок сдвинулся), новый абонемент начинается со сброшенным флагом.
 */
export async function remindEndingSubscriptions(now: Date = new Date()): Promise<number> {
  const db = getFirestore();
  const settings = await loadSettings();
  const today = studioDay(now);
  // Осталось N дней, включая сегодня: последний день не позже today + N − 1.
  const lastDay = addDays(today, settings.endingSoonDays - 1);
  const candidates = await db
    .collection(Collections.subscriptions)
    .where('isCurrent', '==', true)
    .where('endDate', '>=', today)
    .where('endDate', '<=', lastDay)
    .get();

  let reminded = 0;
  for (const doc of candidates.docs) {
    if (doc.get('notified.endingSoon') === true || doc.get('expiredAt')) continue;
    const claimed = await db
      .runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        if (snap.get('notified.endingSoon') === true || snap.get('isCurrent') !== true) return null;
        tx.update(doc.ref, { 'notified.endingSoon': true });
        return { clientId: String(snap.get('clientId')), endDate: String(snap.get('endDate')) };
      })
      .catch((error: unknown) => {
        logger.error('Не удалось отметить напоминание', { subscriptionId: doc.id, error });
        return null;
      });
    if (!claimed) continue;

    reminded++;
    const daysLeft = daysBetween(today, claimed.endDate) + 1;
    await notifyAfterCommit([claimed.clientId], {
      kind: 'subscription_ending_soon',
      title: 'Абонемент скоро закончится',
      body:
        daysLeft <= 1
          ? 'Сегодня последний день абонемента. Продлите его у тренера.'
          : `Абонемент действует до ${ruDate(claimed.endDate)} включительно — осталось ` +
            `${daysLeft} дн. Продлите его у тренера.`,
      data: { subscriptionId: doc.id },
    });
  }
  return reminded;
}

/**
 * Ежедневно в 00:05 по Москве — сразу после конца последнего дня абонемента:
 * сначала истечение и сгорание, затем напоминания «скоро закончится».
 */
export const expireSubscriptionsDaily = onSchedule(
  { schedule: '5 0 * * *', timeZone: STUDIO_TIMEZONE, region: REGION, retryCount: 3 },
  async () => {
    await expireSubscriptions();
    await remindEndingSubscriptions();
  },
);

/**
 * Запустить ту же проверку сейчас — только администратору (например, если
 * плановый запуск не прошёл из-за сбоя). Результат тот же, что у ночного.
 */
export const runSubscriptionExpiry = onCall({ region: REGION }, async (request) => {
  await requireAdmin(request);
  const result = await expireSubscriptions();
  const reminded = await remindEndingSubscriptions();
  return { ...result, reminded };
});
