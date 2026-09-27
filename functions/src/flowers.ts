import { DocumentReference, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { requireUser } from './auth.js';
import { Collections, REGION, STUDIO_TIMEZONE } from './config.js';
import { studioDay } from './time.js';

/**
 * Цветок месяца в профиле (ТЗ 4, 12).
 *
 * Каждый календарный месяц у пользователя новый цветок из справочника
 * `flowers`. Цветок не повторяется три месяца подряд: новый не совпадает
 * с цветками двух предыдущих месяцев. В профиле хранятся
 * `monthlyFlower: { month: 'YYYY-MM', flowerId }` и `recentFlowerIds` —
 * цветки двух предыдущих месяцев (сначала более поздний).
 */

const monthOf = (now: Date) => studioDay(now).slice(0, 7);

/** Выбор нового цветка. [random] подменяется в тестах. */
export function pickFlower(
  flowerIds: readonly string[],
  excluded: readonly string[],
  random: () => number = Math.random,
): string | null {
  const allowed = flowerIds.filter((id) => !excluded.includes(id));
  const pool = allowed.length > 0 ? allowed : flowerIds;
  if (pool.length === 0) return null;
  return pool[Math.floor(random() * pool.length)] ?? pool[0];
}

async function loadFlowerIds(): Promise<string[]> {
  const snap = await getFirestore().collection(Collections.flowers).get();
  return snap.docs.map((d) => d.id);
}

/**
 * Назначить цветок на месяц [month], если его ещё нет. Транзакция: два
 * одновременных вызова не выдадут два разных цветка.
 */
async function assignFlower(
  userRef: DocumentReference,
  month: string,
  flowerIds: readonly string[],
): Promise<{ flowerId: string; assigned: boolean } | null> {
  return getFirestore().runTransaction(async (tx) => {
    const user = await tx.get(userRef);
    if (!user.exists) return null;
    const current = user.get('monthlyFlower') as { month?: string; flowerId?: string } | undefined;
    if (current?.month === month && current.flowerId) {
      return { flowerId: current.flowerId, assigned: false };
    }

    const recent = (user.get('recentFlowerIds') as string[] | undefined) ?? [];
    // Два предыдущих месяца: цветок прошлого месяца и самый поздний из истории.
    const previous = [current?.flowerId, ...recent].filter((id): id is string => !!id).slice(0, 2);
    const flowerId = pickFlower(flowerIds, previous);
    if (!flowerId) return null;

    tx.update(userRef, {
      monthlyFlower: { month, flowerId },
      recentFlowerIds: previous,
    });
    return { flowerId, assigned: true };
  });
}

/**
 * Цветок текущего месяца для вызывающего. Приложение вызывает при открытии
 * главного экрана, если цветка на этот месяц ещё нет (новый пользователь,
 * или ночной запуск 1-го числа не дошёл до него).
 */
export const ensureMonthlyFlower = onCall({ region: REGION }, async (request) => {
  const caller = await requireUser(request);
  const month = monthOf(new Date());
  const result = await assignFlower(
    getFirestore().collection(Collections.users).doc(caller.uid),
    month,
    await loadFlowerIds(),
  );
  return { month, flowerId: result?.flowerId ?? null };
});

/** 1-го числа каждого месяца в 00:10 по Москве — всем пользователям. */
export const assignMonthlyFlowers = onSchedule(
  { schedule: '10 0 1 * *', timeZone: STUDIO_TIMEZONE, region: REGION, retryCount: 3 },
  async () => {
    const month = monthOf(new Date());
    const flowerIds = await loadFlowerIds();
    const users = await getFirestore().collection(Collections.users).get();
    let assigned = 0;
    for (const user of users.docs) {
      const result = await assignFlower(user.ref, month, flowerIds).catch((error: unknown) => {
        logger.error('Не удалось назначить цветок', { uid: user.id, error });
        return null;
      });
      if (result?.assigned) assigned++;
    }
    logger.info('Цветки месяца назначены', { month, assigned, users: users.size });
  },
);
