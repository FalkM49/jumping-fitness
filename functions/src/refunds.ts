import {
  DocumentReference,
  DocumentSnapshot,
  Transaction,
  getFirestore,
} from 'firebase-admin/firestore';

import { Collections } from './config.js';

/**
 * Возврат тренировки на абонемент — при отмене записи клиентом, удалении
 * клиента тренером и отмене всей тренировки (ТЗ 3.1, 3.2).
 *
 * Куда возвращать (решение схемы данных, вопрос 1):
 * 1. в абонемент, с которого тренировка была списана, если он ещё текущий;
 * 2. иначе — в текущий абонемент клиента (старый уже продлён);
 * 3. если текущего нет — в исходный, чтобы возврат был виден в истории.
 * Если выбранный абонемент уже истёк по сроку, тренировку на нём всё равно
 * не использовать — она учитывается как сгоревшая, а не «висит» на счету.
 */
export interface RefundPlan {
  ref: DocumentReference;
  trainingsLeft: number;
  burnedTrainings: number;
  expired: boolean;
}

export interface BookingForRefund {
  clientId: string;
  subscriptionId: string;
}

const subscriptions = () => getFirestore().collection(Collections.subscriptions);

/** Фаза чтения транзакции. */
export async function planRefund(
  tx: Transaction,
  booking: BookingForRefund,
  today: string,
): Promise<RefundPlan | null> {
  const original = await tx.get(subscriptions().doc(booking.subscriptionId));
  const ownedCurrent = (snap: DocumentSnapshot) =>
    snap.exists && snap.get('isCurrent') === true && snap.get('clientId') === booking.clientId;

  let target = ownedCurrent(original) ? original : null;
  if (!target) {
    const user = await tx.get(getFirestore().collection(Collections.users).doc(booking.clientId));
    const currentId = user.get('currentSubscriptionId');
    if (typeof currentId === 'string' && currentId !== booking.subscriptionId) {
      const current = await tx.get(subscriptions().doc(currentId));
      if (ownedCurrent(current)) target = current;
    }
  }
  target ??= original.exists ? original : null;
  if (!target) return null;

  return {
    ref: target.ref,
    trainingsLeft: Number(target.get('trainingsLeft') ?? 0),
    burnedTrainings: Number(target.get('burnedTrainings') ?? 0),
    expired: String(target.get('endDate')) < today,
  };
}

/** Фаза записи транзакции. */
export function applyRefund(tx: Transaction, plan: RefundPlan): void {
  if (plan.expired) {
    tx.update(plan.ref, { burnedTrainings: plan.burnedTrainings + 1 });
  } else {
    tx.update(plan.ref, { trainingsLeft: plan.trainingsLeft + 1 });
  }
}
