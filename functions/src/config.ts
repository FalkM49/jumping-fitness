/**
 * Регион Cloud Functions. Франкфурт — ближайший к Москве регион Firebase.
 * Тот же регион записан в приложении: lib/services/cloud_functions.dart.
 */
export const REGION = 'europe-west3';

/**
 * Регион триггеров Firestore: должен совпадать с регионом базы данных.
 * При создании базы выбирается расположение europe-west3 (Франкфурт) —
 * см. ИНСТРУКЦИЯ_ПО_ЭКСПЛУАТАЦИИ.md. Если база создана в другом месте,
 * поменять здесь (для мультирегиона eur3 — 'europe-west1').
 */
export const FIRESTORE_TRIGGER_REGION = 'europe-west3';

/** Часовой пояс студии: все «дни» и расписание — по Москве (ТЗ, схема данных). */
export const STUDIO_TIMEZONE = 'Europe/Moscow';

/** Имена коллекций — как в lib/models/firestore_paths.dart. */
export const Collections = {
  users: 'users',
  trainerRequests: 'trainer_requests',
  settings: 'settings',
  calendarSlots: 'calendar_slots',
  trainings: 'trainings',
  bookings: 'bookings',
  subscriptions: 'subscriptions',
  flowers: 'flowers',
} as const;

/**
 * Разумные границы значений, которые вводит тренер. Защищают от опечаток
 * («1300 мест») и от попыток записать в базу мусор через прямой вызов.
 */
export const Limits = {
  capacity: { min: 1, max: 100 },
  durationMinutes: { min: 15, max: 300 },
  subscriptionTrainings: { min: 1, max: 200 },
  subscriptionDays: { min: 1, max: 366 },
  freezeLimitDays: { min: 0, max: 60 },
} as const;
