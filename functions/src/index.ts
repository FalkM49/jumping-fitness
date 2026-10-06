/**
 * Cloud Functions Jumping Fitness — вся строгая бизнес-логика (ТЗ 8).
 *
 * Всё, что влияет на роли, места, тренировки на счету и сроки, пишется
 * только отсюда: Admin SDK обходит Security Rules, а приложению прямая
 * запись в эти поля запрещена (docs/02_firestore_schema.md).
 * Описание каждой функции для экранов — docs/04_cloud_functions.md.
 *
 * Где работает: в Yandex Cloud Functions (точка входа — yandex.ts) или,
 * при тарифе Blaze, в Firebase Cloud Functions. Код функций один и тот же.
 */
import { cert, initializeApp } from 'firebase-admin/app';

// Вне Google Cloud (Yandex Cloud) доступ к Firebase — по ключу сервисного
// аккаунта из переменной окружения (секрет Lockbox). В Firebase и в
// эмуляторах переменной нет — доступ выдаётся автоматически.
const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT;
initializeApp(serviceAccount ? { credential: cert(JSON.parse(serviceAccount)) } : undefined);

// Клиент
export { bookTraining, cancelBooking } from './bookings.js';
export { freezeSubscription } from './subscriptions.js';
export { ensureMonthlyFlower } from './flowers.js';
export { notifyTrainerRequest } from './trainer_requests.js';
export { reportClientError } from './client_errors.js';

// Тренер и администратор
export { createTraining, updateTraining, cancelTraining } from './trainings.js';
export { removeClientFromTraining } from './bookings.js';
export { renewSubscription } from './subscriptions.js';

// Только администратор
export { approveTrainerRequest, rejectTrainerRequest } from './trainer_requests.js';
export { runSubscriptionExpiry } from './expiry.js';

// Триггеры (только Firebase Cloud Functions)
export { onTrainerRequestCreated } from './trainer_requests.js';

// По расписанию
export { expireSubscriptionsDaily } from './expiry.js';
export { assignMonthlyFlowers } from './flowers.js';
