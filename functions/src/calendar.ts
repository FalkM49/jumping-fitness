import {
  DocumentReference,
  FieldValue,
  Timestamp,
  Transaction,
  getFirestore,
} from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

import { TrainingTarget } from './args.js';
import { Collections } from './config.js';
import { Settings } from './settings.js';
import { DaySlot, isoWeekday, slotKeyOf, studioInstant } from './time.js';

/**
 * Календарь: тренировки и ячейки (docs/02_firestore_schema.md, 2.4–2.5).
 *
 * Тренировка по расписанию по умолчанию (пн/ср/пт) — «виртуальная»: пока
 * никто на неё не записался и тренер её не трогал, документа нет, приложение
 * рисует её по settings/defaults. Документ создаётся («материализуется»)
 * в той же транзакции, что и первая запись или первая правка тренером.
 */

export type TrainingStatus = 'scheduled' | 'cancelled';

export interface TrainingDoc {
  slotKey: string;
  date: string;
  slot: DaySlot;
  startTime: string;
  startAt: Timestamp;
  durationMinutes: number;
  capacity: number;
  bookedCount: number;
  status: TrainingStatus;
  source: 'default' | 'manual';
}

export interface ResolvedTraining {
  ref: DocumentReference;
  data: TrainingDoc;
  /** Тренировка по расписанию, документа ещё нет — создать при записи. */
  virtual: boolean;
  slotRef: DocumentReference;
}

const db = () => getFirestore();

export const trainingRef = (id: string) => db().collection(Collections.trainings).doc(id);
export const slotRef = (key: string) => db().collection(Collections.calendarSlots).doc(key);

/** ID материализованной тренировки по умолчанию — детерминированный, чтобы
 * две одновременные первые записи не создали два документа. */
export const defaultTrainingId = (slotKey: string) => `default_${slotKey}`;

/**
 * Что стоит в ячейке или какая тренировка имеется в виду. Только чтение —
 * вызывать в фазе чтения транзакции. `null` — ячейка пуста.
 */
export async function resolveTraining(
  tx: Transaction,
  target: TrainingTarget,
  settings: Settings,
): Promise<ResolvedTraining | null> {
  if (target.kind === 'training') {
    const ref = trainingRef(target.trainingId);
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Тренировка не найдена.');
    const data = snap.data() as TrainingDoc;
    return { ref, data, virtual: false, slotRef: slotRef(data.slotKey) };
  }

  const key = slotKeyOf(target.date, target.slot);
  const cellRef = slotRef(key);
  const cell = await tx.get(cellRef);

  if (cell.exists) {
    const activeId = cell.get('activeTrainingId');
    if (typeof activeId !== 'string') return null;
    const ref = trainingRef(activeId);
    const snap = await tx.get(ref);
    if (!snap.exists) return null;
    return { ref, data: snap.data() as TrainingDoc, virtual: false, slotRef: cellRef };
  }

  // Ячейку не трогали: тренировка есть, только если день — по расписанию.
  if (!settings.weekdays.includes(isoWeekday(target.date))) return null;

  const ref = trainingRef(defaultTrainingId(key));
  const existing = await tx.get(ref);
  if (existing.exists) {
    // Документ есть, а ячейки нет (сбой в прошлом) — чиним ячейку при записи.
    return { ref, data: existing.data() as TrainingDoc, virtual: true, slotRef: cellRef };
  }

  const startTime = target.slot === 'morning' ? settings.morningTime : settings.eveningTime;
  return {
    ref,
    virtual: true,
    slotRef: cellRef,
    data: {
      slotKey: key,
      date: target.date,
      slot: target.slot,
      startTime,
      startAt: Timestamp.fromDate(studioInstant(target.date, startTime)),
      durationMinutes: settings.durationMinutes,
      capacity: settings.capacity,
      bookedCount: 0,
      status: 'scheduled',
      source: 'default',
    },
  };
}

/**
 * Создать документы виртуальной тренировки (с уже изменёнными полями
 * [data]) и её ячейки. Фаза записи транзакции.
 */
export function materialize(
  tx: Transaction,
  training: ResolvedTraining,
  data: TrainingDoc,
  updatedBy: string | null = null,
): void {
  tx.set(training.ref, {
    ...data,
    createdAt: FieldValue.serverTimestamp(),
    // Тренировку по расписанию никто не «создавал» (схема данных, 2.5).
    createdBy: null,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy,
  });
  tx.set(training.slotRef, {
    date: data.date,
    slot: data.slot,
    activeTrainingId: training.ref.id,
    overridesDefault: false,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

/** Тренировка уже началась (по серверному времени). */
export function hasStarted(training: TrainingDoc, now: Date): boolean {
  return training.startAt.toMillis() <= now.getTime();
}
