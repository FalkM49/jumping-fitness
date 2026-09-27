import { getFirestore } from 'firebase-admin/firestore';

import { Collections } from './config.js';
import { isTimeKey, slotOfTime } from './time.js';

/**
 * Значения по умолчанию (ТЗ 7) из settings/defaults. Если документа или
 * поля нет — те же значения, что в приложении (AppSettings.fallback).
 */
export interface Settings {
  weekdays: number[];
  morningTime: string;
  eveningTime: string;
  durationMinutes: number;
  capacity: number;
  cancelWindowHours: number;
  freezeLimitDays: number;
  /** Порог «абонемент скоро закончится» в днях (ТЗ 5 п. 1, ТЗ 13). */
  endingSoonDays: number;
  /** Порог «осталось мало тренировок» (ТЗ 5 п. 2). */
  lowTrainingsThreshold: number;
}

export const FALLBACK_SETTINGS: Settings = {
  weekdays: [1, 3, 5],
  morningTime: '08:10',
  eveningTime: '18:00',
  durationMinutes: 60,
  capacity: 13,
  cancelWindowHours: 3,
  freezeLimitDays: 3,
  endingSoonDays: 5,
  lowTrainingsThreshold: 1,
};

function positiveInt(value: unknown, fallback: number, min = 1): number {
  return typeof value === 'number' && Number.isInteger(value) && value >= min ? value : fallback;
}

export async function loadSettings(): Promise<Settings> {
  const snap = await getFirestore().collection(Collections.settings).doc('defaults').get();
  const data = snap.data() ?? {};
  const training = (data.training ?? {}) as Record<string, unknown>;
  const subscription = (data.subscription ?? {}) as Record<string, unknown>;
  const rules = (data.rules ?? {}) as Record<string, unknown>;
  const f = FALLBACK_SETTINGS;

  const weekdays = Array.isArray(training.weekdays)
    ? training.weekdays.filter((d): d is number => Number.isInteger(d) && d >= 1 && d <= 7)
    : f.weekdays;
  // Время обязано попадать в свою строку сетки — иначе берём значение из ТЗ.
  const morning = isTimeKey(training.morningTime) && slotOfTime(training.morningTime) === 'morning'
    ? training.morningTime
    : f.morningTime;
  const evening = isTimeKey(training.eveningTime) && slotOfTime(training.eveningTime) === 'evening'
    ? training.eveningTime
    : f.eveningTime;

  return {
    weekdays,
    morningTime: morning,
    eveningTime: evening,
    durationMinutes: positiveInt(training.durationMinutes, f.durationMinutes),
    capacity: positiveInt(training.capacity, f.capacity),
    cancelWindowHours: positiveInt(rules.cancelWindowHours, f.cancelWindowHours, 0),
    freezeLimitDays: positiveInt(subscription.freezeLimitDays, f.freezeLimitDays, 0),
    endingSoonDays: positiveInt(rules.endingSoonDays, f.endingSoonDays, 0),
    lowTrainingsThreshold: positiveInt(rules.lowTrainingsThreshold, f.lowTrainingsThreshold, 0),
  };
}
