import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';

import { argsOf, docId } from './args.js';
import { requireAdmin, requireUser } from './auth.js';
import { Collections, FIRESTORE_TRIGGER_REGION, REGION } from './config.js';
import { notifyAfterCommit } from './notifications.js';

type Decision = 'approved' | 'rejected';

/** Одобрить заявку в тренеры: заявка → approved, users.role → trainer. */
export const approveTrainerRequest = onCall({ region: REGION }, (request) =>
  decide(request, 'approved'),
);

/** Отклонить заявку в тренеры: заявка → rejected, роль не меняется. */
export const rejectTrainerRequest = onCall({ region: REGION }, (request) =>
  decide(request, 'rejected'),
);

/**
 * Решение по заявке (ТЗ 2, 8.1). Вызывать может только администратор.
 * Аргументы: `{ uid }` заявителя.
 * Заявка и роль меняются в одной транзакции: двойное нажатие или
 * одновременное решение с двух устройств не пройдут — второе увидит,
 * что заявка уже не pending.
 */
async function decide(request: CallableRequest<unknown>, decision: Decision) {
  const admin = await requireAdmin(request);
  const uid = docId(argsOf(request.data), 'uid', 'пользователь');

  const db = getFirestore();
  const requestRef = db.collection(Collections.trainerRequests).doc(uid);
  const userRef = db.collection(Collections.users).doc(uid);

  await db.runTransaction(async (tx) => {
    const [requestSnap, userSnap] = await Promise.all([tx.get(requestRef), tx.get(userRef)]);
    if (!requestSnap.exists) {
      throw new HttpsError('not-found', 'Заявка не найдена.');
    }
    if (requestSnap.get('status') !== 'pending') {
      throw new HttpsError('failed-precondition', 'Эта заявка уже рассмотрена.');
    }
    if (decision === 'approved' && !userSnap.exists) {
      throw new HttpsError('failed-precondition', 'Профиль пользователя не найден.');
    }

    tx.update(requestRef, {
      status: decision,
      decidedAt: FieldValue.serverTimestamp(),
      decidedBy: admin.uid,
    });
    if (decision === 'approved') {
      tx.update(userRef, { role: 'trainer' });
    }
  });

  logger.info('Решение по заявке в тренеры', { uid, decision, adminUid: admin.uid });

  await notifyAfterCommit(
    [uid],
    decision === 'approved'
      ? {
          kind: 'trainer_request_approved',
          title: 'Заявка одобрена',
          body: 'Теперь у вас есть права тренера в Jumping Fitness.',
        }
      : {
          kind: 'trainer_request_rejected',
          title: 'Заявка в тренеры отклонена',
          body: 'Администратор отклонил заявку. Вы по-прежнему пользуетесь приложением как клиент.',
        },
  );

  return { uid, status: decision };
}

/**
 * Новая заявка в тренеры — уведомление администраторам (флаг isAdmin, ТЗ 2).
 *
 * Заявку создаёт само приложение при регистрации (правила это разрешают).
 * Уведомить может триггер на создание документа (Firebase Cloud Functions)
 * или само приложение сразу после регистрации — `notifyTrainerRequest`
 * (Yandex Cloud: триггеров Firestore там нет). Отметка `adminsNotifiedAt`
 * в заявке гарантирует, что администратор получит уведомление один раз.
 */
async function notifyAdminsAboutRequest(uid: string): Promise<boolean> {
  const db = getFirestore();
  const requestRef = db.collection(Collections.trainerRequests).doc(uid);
  const fullName = await db.runTransaction(async (tx) => {
    const snap = await tx.get(requestRef);
    if (!snap.exists || snap.get('status') !== 'pending' || snap.get('adminsNotifiedAt')) {
      return null;
    }
    tx.update(requestRef, { adminsNotifiedAt: FieldValue.serverTimestamp() });
    return String(snap.get('fullName') ?? 'Пользователь');
  });
  if (fullName === null) return false;

  const admins = await db.collection(Collections.users).where('isAdmin', '==', true).get();
  await notifyAfterCommit(
    admins.docs.map((d) => d.id),
    {
      kind: 'trainer_request_new',
      title: 'Новая заявка в тренеры',
      body: `${fullName} хочет стать тренером.`,
      data: { uid },
    },
  );
  return true;
}

export const onTrainerRequestCreated = onDocumentCreated(
  { document: `${Collections.trainerRequests}/{uid}`, region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    await notifyAdminsAboutRequest(event.params.uid);
  },
);

/**
 * Приложение сообщает о своей только что поданной заявке. Только о своей:
 * uid берётся из входа, а не из аргументов. Повторный вызов ничего не шлёт.
 */
export const notifyTrainerRequest = onCall({ region: REGION }, async (request) => {
  const caller = await requireUser(request);
  return { notified: await notifyAdminsAboutRequest(caller.uid) };
});
