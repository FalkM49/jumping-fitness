import { HttpsError } from 'firebase-functions/v2/https';

import { DaySlot, isDayKey, isTimeKey } from './time.js';

/**
 * Разбор аргументов вызова. Всё, что пришло с телефона, считается
 * непроверенным: неверный тип или значение → invalid-argument с понятным
 * текстом, а не падение функции где-то в середине транзакции.
 */

export type Args = Record<string, unknown>;

function invalid(message: string): never {
  throw new HttpsError('invalid-argument', message);
}

export function argsOf(data: unknown): Args {
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    invalid('Неверный формат запроса.');
  }
  return data as Args;
}

/** ID документа: непустая строка без «/». */
export function docId(args: Args, key: string, what: string): string {
  const value = args[key];
  if (typeof value !== 'string' || value.length === 0 || value.length > 128 || value.includes('/')) {
    invalid(`Не указан ${what}.`);
  }
  return value;
}

export function int(args: Args, key: string, what: string, range: { min: number; max: number }): number {
  const value = args[key];
  if (typeof value !== 'number' || !Number.isInteger(value)) invalid(`${what}: нужно целое число.`);
  if (value < range.min || value > range.max) {
    invalid(`${what}: допустимо от ${range.min} до ${range.max}.`);
  }
  return value;
}

export function optionalInt(
  args: Args,
  key: string,
  what: string,
  range: { min: number; max: number },
): number | undefined {
  return args[key] === undefined || args[key] === null ? undefined : int(args, key, what, range);
}

export function day(args: Args, key: string, what: string): string {
  const value = args[key];
  if (!isDayKey(value)) invalid(`${what}: нужна дата в формате ГГГГ-ММ-ДД.`);
  return value;
}

export function time(args: Args, key: string): string {
  const value = args[key];
  if (!isTimeKey(value)) invalid('Время: нужен формат ЧЧ:ММ.');
  return value;
}

export function optionalTime(args: Args, key: string): string | undefined {
  return args[key] === undefined || args[key] === null ? undefined : time(args, key);
}

export function slot(args: Args, key = 'slot'): DaySlot {
  const value = args[key];
  if (value !== 'morning' && value !== 'evening') invalid('Не указано: утро или вечер.');
  return value;
}

/**
 * Какая тренировка: существующая `{ trainingId }` или ячейка календаря
 * `{ date, slot }` — для тренировки по расписанию, которой ещё нет в базе.
 */
export type TrainingTarget =
  | { kind: 'training'; trainingId: string }
  | { kind: 'cell'; date: string; slot: DaySlot };

export function trainingTarget(args: Args): TrainingTarget {
  if (args.trainingId !== undefined && args.trainingId !== null) {
    return { kind: 'training', trainingId: docId(args, 'trainingId', 'тренировка') };
  }
  return { kind: 'cell', date: day(args, 'date', 'Дата'), slot: slot(args) };
}
