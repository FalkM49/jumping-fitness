import { getFirestore } from 'firebase-admin/firestore';
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

import { Collections } from './config.js';

/**
 * Проверка вызывающего (ТЗ 8.1, 8.4). Роль читается из профиля в Firestore,
 * а не из токена и не из аргументов: флаг isAdmin ставится вручную
 * в Firebase Console, а роль trainer — только функцией одобрения заявки.
 */

export interface Caller {
  uid: string;
  fullName: string;
  role: 'client' | 'trainer';
  isAdmin: boolean;
}

/** Тренер или администратор (у админа все права тренера). */
export function isStaff(caller: Caller): boolean {
  return caller.role === 'trainer' || caller.isAdmin;
}

/** Вошедший и зарегистрированный пользователь. */
export async function requireUser(request: CallableRequest<unknown>): Promise<Caller> {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Нужно войти в приложение.');
  }
  const profile = await getFirestore().collection(Collections.users).doc(uid).get();
  if (!profile.exists) {
    throw new HttpsError('permission-denied', 'Сначала завершите регистрацию.');
  }
  const role = profile.get('role');
  return {
    uid,
    fullName: String(profile.get('fullName') ?? ''),
    role: role === 'trainer' ? 'trainer' : 'client',
    isAdmin: profile.get('isAdmin') === true,
  };
}

/** Тренер или администратор. */
export async function requireStaff(request: CallableRequest<unknown>): Promise<Caller> {
  const caller = await requireUser(request);
  if (!isStaff(caller)) {
    throw new HttpsError('permission-denied', 'Действие доступно только тренеру.');
  }
  return caller;
}

/** Только администратор (флаг isAdmin). */
export async function requireAdmin(request: CallableRequest<unknown>): Promise<Caller> {
  const caller = await requireUser(request);
  if (!caller.isAdmin) {
    throw new HttpsError('permission-denied', 'Действие доступно только администратору.');
  }
  return caller;
}

/**
 * Отказ по бизнес-правилу: текст — для пользователя, `reason` — для
 * приложения (например, чтобы у кнопки «Записаться» показать (i) с причиной,
 * ТЗ 3.1). Код failed-precondition: приложение показывает текст как есть.
 */
export function refuse(reason: string, message: string): never {
  throw new HttpsError('failed-precondition', message, { reason });
}
