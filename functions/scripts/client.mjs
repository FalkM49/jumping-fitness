// Создать в ЛОКАЛЬНЫХ эмуляторах клиента с действующим абонементом —
// чтобы посмотреть экраны клиента.
//
//   npm run dev:client -- irina@mail.ru "Ирина Волкова" +79163334455
//
// Аккаунт — с уже подтверждённой почтой, пароль password123. Абонемент
// (как будто его оформил тренер): начался 10 дней назад, действует ещё
// 20 дней, 11 тренировок, осталось 8. Затем войдите в приложение с этой почтой.

import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

import { DEV_PASSWORD, PROJECT_ID, normalizePhone, signInVerified } from './dev-auth.mjs';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

const [emailArg, fullName = 'Ирина Волкова', phoneArg = '+79163334455'] = process.argv.slice(2);
const email = emailArg?.trim().toLowerCase();
const phone = normalizePhone(phoneArg);
if (!email?.includes('@') || !phone) {
  console.error('Укажите почту и, по желанию, ФИО в кавычках и телефон: irina@mail.ru "Ирина Волкова" +79163334455');
  process.exit(1);
}

// 1. Аккаунт с подтверждённой почтой.
const { uid } = await signInVerified(email);
// 2. Профиль и абонемент.
initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();
const userRef = db.doc(`users/${uid}`);
if (!(await userRef.get()).exists) {
  await userRef.set({ fullName, phone, role: 'client', isAdmin: false, createdAt: FieldValue.serverTimestamp() });
}

const day = (offset) => {
  const d = new Date(Date.now() + 3 * 3600e3 + offset * 86400e3);
  return d.toISOString().slice(0, 10);
};
const subRef = db.collection('subscriptions').doc();
await subRef.set({
  clientId: uid,
  isCurrent: true,
  startDate: day(-10),
  endDate: day(19),
  originalEndDate: day(19),
  trainingsTotal: 11,
  trainingsLeft: 8,
  freezeLimitDays: 3,
  freeze: null,
  expiredAt: null,
  burnedTrainings: 0,
  notified: { endingSoon: false, lowTrainings: false, expired: false },
  createdAt: FieldValue.serverTimestamp(),
  createdBy: null,
  closedAt: null,
});
await userRef.update({ currentSubscriptionId: subRef.id });

console.log(`Готово: клиент ${fullName} (${email}, пароль ${DEV_PASSWORD}), абонемент по ${day(19)}, осталось 8 из 11.`);
