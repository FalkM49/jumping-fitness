/**
 * Время студии. Москва живёт в UTC+3 круглый год (без перехода на летнее
 * время с 2014 года), поэтому хватает фиксированного смещения — так же,
 * как в приложении (lib/models/calendar_day.dart).
 *
 * «День» — строка `YYYY-MM-DD` по Москве, «время» — `HH:mm`.
 * Все расчёты — от серверного `now`, а не от того, что прислал телефон.
 */

const OFFSET_MS = 3 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Граница строк сетки: утро — начало до 14:00, вечер — с 14:00. */
export const EVENING_STARTS_AT_MINUTES = 14 * 60;

export type DaySlot = 'morning' | 'evening';

/** День студии, в который приходится момент [instant]. */
export function studioDay(instant: Date): string {
  return new Date(instant.getTime() + OFFSET_MS).toISOString().slice(0, 10);
}

/** Существующая дата в формате YYYY-MM-DD (31 февраля — нет). */
export function isDayKey(value: unknown): value is string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).toISOString().slice(0, 10) === value;
}

/** Время HH:mm (00:00–23:59). */
export function isTimeKey(value: unknown): value is string {
  return typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
}

export function addDays(day: string, days: number): string {
  const [y, m, d] = day.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/** Сколько дней от [from] до [to] (может быть отрицательным). */
export function daysBetween(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY_MS);
}

/** ISO-день недели: 1 = понедельник … 7 = воскресенье. */
export function isoWeekday(day: string): number {
  const weekday = new Date(`${day}T00:00:00Z`).getUTCDay();
  return weekday === 0 ? 7 : weekday;
}

/** Момент «день [day], [time] по Москве». */
export function studioInstant(day: string, time: string): Date {
  const [y, m, d] = day.split('-').map(Number);
  const [hh, mm] = time.split(':').map(Number);
  return new Date(Date.UTC(y, m - 1, d, hh, mm) - OFFSET_MS);
}

export function minutesOfDay(time: string): number {
  const [hh, mm] = time.split(':').map(Number);
  return hh * 60 + mm;
}

/** Строка сетки, в которую попадает тренировка с началом в [time]. */
export function slotOfTime(time: string): DaySlot {
  return minutesOfDay(time) < EVENING_STARTS_AT_MINUTES ? 'morning' : 'evening';
}

/** Ключ ячейки = ID документа calendar_slots: `YYYY-MM-DD_morning`. */
export function slotKeyOf(day: string, slot: DaySlot): string {
  return `${day}_${slot}`;
}

const MONTHS_GENITIVE = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

/** Для текстов пользователю: `2026-10-01` → `1 октября`. */
export function ruDate(day: string): string {
  const [, m, d] = day.split('-').map(Number);
  return `${d} ${MONTHS_GENITIVE[m - 1]}`;
}

/** Входит ли день в отрезок [from, to] включительно. Строки YYYY-MM-DD сравниваются как даты. */
export function isWithin(day: string, from: string, to: string): boolean {
  return day >= from && day <= to;
}
