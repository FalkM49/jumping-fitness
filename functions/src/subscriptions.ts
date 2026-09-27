import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { argsOf, day, docId, int } from './args.js';
import { refuse, requireStaff, requireUser } from './auth.js';
import { Collections, Limits, REGION } from './config.js';
import { addDays, daysBetween, ruDate, studioDay } from './time.js';

/**
 * Абонементы (ТЗ 5, 6). Один документ на каждый период: при продлении
 * старый остаётся в истории как есть (`isCurrent: false`), ссылка на
 * текущий — в users/{uid}.currentSubscriptionId.
 */

const db = () => getFirestore();
const userRef = (uid: string) => db().collection(Collections.users).doc(uid);
const subscriptionRef = (id: string) => db().collection(Collections.subscriptions).doc(id);

/**
 * Заморозить свой текущий абонемент (ТЗ 5).
 *
 * Аргументы: `{ days }`. Заморозка начинается сегодня (по Москве)
 * и длится `days` дней включительно. Условия: абонемент действует сегодня,
 * заморозка в этом периоде ещё не использована (даже частично),
 * `days` не больше лимита, который задал тренер при продлении.
 *
 * Дата окончания сдвигается сразу на `days` дней (решение схемы данных,
 * вопрос 2): итог тот же, что при сдвиге на +1 за каждый прошедший день
 * заморозки, но без ежедневной работы и промежуточных состояний.
 * Досрочного выхода из заморозки в ТЗ нет. Уже сделанные записи
 * сохраняются, новые во время заморозки bookTraining не примет.
 */
export const freezeSubscription = onCall({ region: REGION }, async (request) => {
  const caller = await requireUser(request);
  const days = int(argsOf(request.data), 'days', 'Дней заморозки', {
    min: 1,
    max: Limits.freezeLimitDays.max,
  });

  return db().runTransaction(async (tx) => {
    const today = studioDay(new Date());
    const user = await tx.get(userRef(caller.uid));
    const subscriptionId = user.get('currentSubscriptionId');
    const sub = typeof subscriptionId === 'string' ? await tx.get(subscriptionRef(subscriptionId)) : null;
    if (!sub?.exists || sub.get('isCurrent') !== true || sub.get('clientId') !== caller.uid) {
      refuse('no_subscription', 'Нет действующего абонемента.');
    }

    const startDate = String(sub.get('startDate'));
    const endDate = String(sub.get('endDate'));
    const limit = Number(sub.get('freezeLimitDays') ?? 0);
    if (today < startDate || today > endDate) {
      refuse('subscription_inactive', 'Заморозить можно только действующий абонемент.');
    }
    if (sub.get('freeze')) {
      refuse('freeze_used', 'Заморозка в этом периоде абонемента уже использована.');
    }
    if (limit <= 0) {
      refuse('freeze_unavailable', 'Для этого абонемента заморозка не предусмотрена.');
    }
    if (days > limit) {
      refuse('freeze_limit', `Можно заморозить не больше чем на ${limit} дн.`);
    }

    const freeze = { startDate: today, endDate: addDays(today, days - 1), days };
    const newEndDate = addDays(endDate, days);
    tx.update(sub.ref, {
      freeze: { ...freeze, createdAt: FieldValue.serverTimestamp() },
      endDate: newEndDate,
      // Срок сдвинулся — предупреждение «скоро закончится» снова актуально.
      'notified.endingSoon': false,
    });

    logger.info('Заморозка абонемента', { uid: caller.uid, subscriptionId: sub.id, days });
    return { subscriptionId: sub.id, freeze, endDate: newEndDate };
  });
});

/**
 * Продлить или оформить абонемент клиенту (ТЗ 6). Только тренер или админ.
 *
 * Аргументы: `{ clientId, startDate, endDate, trainings, freezeLimitDays }`
 * — все обязательны: приложение предзаполняет их значениями по умолчанию
 * (30 дней, 11 тренировок, 3 дня заморозки, ТЗ 7), тренер правит на месте.
 * Создаётся новый документ абонемента с неиспользованной заморозкой;
 * прежний текущий получает `isCurrent: false` и `closedAt` и остаётся
 * в истории без других изменений. Остаток старого абонемента не переносится.
 */
export const renewSubscription = onCall({ region: REGION }, async (request) => {
  const caller = await requireStaff(request);
  const args = argsOf(request.data);
  const clientId = docId(args, 'clientId', 'клиент');
  const startDate = day(args, 'startDate', 'Дата начала');
  const endDate = day(args, 'endDate', 'Дата окончания');
  const trainings = int(args, 'trainings', 'Количество тренировок', Limits.subscriptionTrainings);
  const freezeLimitDays = int(args, 'freezeLimitDays', 'Лимит заморозки', Limits.freezeLimitDays);

  if (endDate < startDate) {
    throw new HttpsError('invalid-argument', 'Дата окончания раньше даты начала.');
  }
  const lengthDays = daysBetween(startDate, endDate) + 1;
  if (lengthDays > Limits.subscriptionDays.max) {
    throw new HttpsError('invalid-argument', `Абонемент не может быть длиннее ${Limits.subscriptionDays.max} дней.`);
  }
  const today = studioDay(new Date());
  if (endDate < today) {
    refuse('ends_in_past', `Абонемент закончился бы ${ruDate(endDate)} — это уже в прошлом.`);
  }

  const newRef = db().collection(Collections.subscriptions).doc();

  const previousId = await db().runTransaction(async (tx) => {
    const user = await tx.get(userRef(clientId));
    if (!user.exists) throw new HttpsError('not-found', 'Клиент не найден.');
    if (user.get('role') !== 'client') {
      refuse('not_client', 'Абонемент оформляется только клиенту.');
    }
    const currentId = user.get('currentSubscriptionId');
    const current = typeof currentId === 'string' ? await tx.get(subscriptionRef(currentId)) : null;

    if (current?.exists && current.get('isCurrent') === true) {
      tx.update(current.ref, { isCurrent: false, closedAt: FieldValue.serverTimestamp() });
    }
    tx.set(newRef, {
      clientId,
      isCurrent: true,
      startDate,
      endDate,
      originalEndDate: endDate,
      trainingsTotal: trainings,
      trainingsLeft: trainings,
      freezeLimitDays,
      freeze: null,
      expiredAt: null,
      burnedTrainings: 0,
      notified: { endingSoon: false, lowTrainings: false, expired: false },
      createdAt: FieldValue.serverTimestamp(),
      createdBy: caller.uid,
      closedAt: null,
    });
    tx.update(user.ref, { currentSubscriptionId: newRef.id });
    return current?.exists ? current.id : null;
  });

  logger.info('Абонемент продлён', { clientId, subscriptionId: newRef.id, previousId, by: caller.uid });
  return { subscriptionId: newRef.id, previousSubscriptionId: previousId };
});
