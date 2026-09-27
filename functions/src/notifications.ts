import { DocumentReference, FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';

import { Collections, WEB_APP_URL } from './config.js';

/**
 * Уведомления (ТЗ 2, 3.2, 5, 8.5). Каждое уведомление уходит по двум
 * каналам, как требует ТЗ 5:
 *
 * 1. **История внутри приложения** — документ users/{uid}/notifications/{id}.
 *    Приложение показывает её списком и счётчиком непрочитанных, так что
 *    пропущенный push не теряется.
 * 2. **Push через FCM** на все устройства пользователя (users/{uid}/devices).
 *    Токены, которые FCM вернёт как недействительные, удаляются.
 *
 * В `data` push-сообщения — вид уведомления и то, что нужно приложению для
 * перехода по тапу (trainingId, date, slot…).
 */

export type NotificationKind =
  | 'trainer_request_new'
  | 'trainer_request_approved'
  | 'trainer_request_rejected'
  | 'training_changed'
  | 'training_cancelled'
  | 'removed_from_training'
  | 'subscription_ending_soon'
  | 'subscription_low_trainings'
  | 'subscription_expired';

export interface Notification {
  kind: NotificationKind;
  title: string;
  body: string;
  /** Данные для перехода в приложении: только строки (так требует FCM). */
  data?: Record<string, string>;
}

/** Сколько уведомлений храним в истории одного пользователя. */
const HISTORY_LIMIT = 50;

/** Коды FCM, после которых токен устройства больше не годится. */
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

const isEmulator = () => process.env.FUNCTIONS_EMULATOR === 'true';

/**
 * Отправить уведомление пользователям [recipientUids]: запись в историю
 * и push. Сбой push одному получателю не мешает остальным.
 */
export async function sendNotification(
  recipientUids: readonly string[],
  notification: Notification,
): Promise<void> {
  const recipients = [...new Set(recipientUids)];
  if (recipients.length === 0) return;

  await Promise.all(recipients.map((uid) => deliver(uid, notification)));
}

async function deliver(uid: string, notification: Notification): Promise<void> {
  const db = getFirestore();
  const user = db.collection(Collections.users).doc(uid);
  const data = { kind: notification.kind, ...(notification.data ?? {}) };

  // 1. История — всегда, даже если у пользователя нет ни одного устройства.
  const record = user.collection('notifications').doc();
  await record.set({
    kind: notification.kind,
    title: notification.title,
    body: notification.body,
    data,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });
  await trimHistory(uid);

  // 2. Push.
  const devices = await user.collection('devices').get();
  const tokens = devices.docs
    .map((d) => ({ ref: d.ref, token: d.get('token') }))
    .filter((d): d is { ref: DocumentReference; token: string } =>
      typeof d.token === 'string' && d.token.length > 0,
    );
  if (tokens.length === 0) return;

  if (isEmulator()) {
    // У эмулятора нет FCM: настоящий push уйдёт после подключения проекта
    // (этап 8). История выше уже записана — её видно в приложении.
    logger.info('Эмулятор: push не отправляется', { uid, kind: notification.kind });
    return;
  }

  const response = await getMessaging().sendEachForMulticast({
    tokens: tokens.map((t) => t.token),
    notification: { title: notification.title, body: notification.body },
    data: { ...data, notificationId: record.id },
    android: {
      priority: 'high',
      notification: { tag: notification.kind, color: '#C81E5E' },
    },
    apns: { payload: { aps: { sound: 'default' } } },
    // Веб-версия: значок и куда вести по тапу (браузер откроет приложение).
    webpush: {
      notification: { icon: '/icons/Icon-192.png', tag: notification.kind },
      fcmOptions: { link: WEB_APP_URL },
    },
  });

  const dead = response.responses
    .map((r, i) => (!r.success && DEAD_TOKEN_CODES.has(r.error?.code ?? '') ? tokens[i].ref : null))
    .filter((ref): ref is DocumentReference => ref !== null);
  await Promise.all(dead.map((ref) => ref.delete()));
  if (response.failureCount > 0) {
    logger.warn('Часть push не доставлена', {
      uid,
      kind: notification.kind,
      failed: response.failureCount,
      removedTokens: dead.length,
    });
  }
}

/** История не растёт бесконечно: оставляем последние HISTORY_LIMIT. */
async function trimHistory(uid: string): Promise<void> {
  const old = await getFirestore()
    .collection(Collections.users)
    .doc(uid)
    .collection('notifications')
    .orderBy('createdAt', 'desc')
    .offset(HISTORY_LIMIT)
    .get();
  await Promise.all(old.docs.map((d) => d.ref.delete()));
}

/**
 * Уведомление после уже записанного изменения: сбой отправки не должен
 * превращать успешное действие в ошибку для того, кто его выполнил.
 */
export async function notifyAfterCommit(
  recipientUids: readonly string[],
  notification: Notification,
): Promise<void> {
  try {
    await sendNotification(recipientUids, notification);
  } catch (error) {
    logger.error('Не удалось отправить уведомление', { kind: notification.kind, error });
  }
}
