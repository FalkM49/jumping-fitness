// Общие помощники тестов Cloud Functions на эмуляторах.
// Порты — из firebase.test.json (отдельные от эмуляторов для разработки).

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { Timestamp, doc, getDoc, getDocs, collection, setDoc } from 'firebase/firestore';

export const PROJECT_ID = 'demo-jumping-fitness';
export const REGION = 'europe-west3';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9199';
// Куда слать вызовы: эмулятор Functions или локальный адаптер Yandex
// (npm run test:yandex задаёт CALLABLE_BASE).
const CALLABLE_BASE =
  process.env.CALLABLE_BASE ?? `http://127.0.0.1:5101/${PROJECT_ID}/${REGION}`;

export { Timestamp };

/** @type {import('@firebase/rules-unit-testing').RulesTestEnvironment} */
let env;

export async function startEnv() {
  env = await initializeTestEnvironment({ projectId: PROJECT_ID });
  return env;
}

export async function stopEnv() {
  await env?.cleanup();
}

export const clearDb = () => env.clearFirestore();

/** Новый пользователь в эмуляторе Auth: { uid, idToken }. */
export async function signUp() {
  const response = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' },
  );
  const body = await response.json();
  return { uid: body.localId, idToken: body.idToken };
}

/** Вызов callable-функции: { result } или { error: { status, message, details } }. */
export async function call(name, data, user) {
  const response = await fetch(`${CALLABLE_BASE}/${name}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(user ? { Authorization: `Bearer ${user.idToken}` } : {}),
    },
    body: JSON.stringify({ data }),
  });
  return response.json();
}

export async function seed(path, data) {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path), data));
}

export async function read(path) {
  let data;
  await env.withSecurityRulesDisabled(async (ctx) => {
    data = (await getDoc(doc(ctx.firestore(), path))).data();
  });
  return data;
}

export async function readAll(path) {
  let docs;
  await env.withSecurityRulesDisabled(async (ctx) => {
    docs = (await getDocs(collection(ctx.firestore(), path))).docs.map((d) => ({ id: d.id, ...d.data() }));
  });
  return docs;
}

// ---------------------------------------------------------------- время студии

const MSK_MS = 3 * 60 * 60 * 1000;
const HOUR = 60 * 60 * 1000;
export const hours = (n) => n * HOUR;

export const dayOf = (ms) => new Date(ms + MSK_MS).toISOString().slice(0, 10);
export const today = () => dayOf(Date.now());
export function addDays(day, n) {
  const [y, m, d] = day.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}
export function isoWeekday(day) {
  const w = new Date(`${day}T00:00:00Z`).getUTCDay();
  return w === 0 ? 7 : w;
}
/** Ближайший день после [from] (не раньше чем через [minDays]) с днём недели из [weekdays]. */
export function nextDay(weekdays, minDays = 2) {
  let day = addDays(today(), minDays);
  while (!weekdays.includes(isoWeekday(day))) day = addDays(day, 1);
  return day;
}

// ---------------------------------------------------------------- данные

export const profile = (fullName, role = 'client', extra = {}) => ({
  fullName,
  phone: '+79990000000',
  role,
  isAdmin: false,
  createdAt: Timestamp.now(),
  ...extra,
});

/** Текущий абонемент: по умолчанию действует с позавчера на месяц вперёд. */
export async function seedSubscription(id, clientId, fields = {}) {
  const data = {
    clientId,
    isCurrent: true,
    startDate: addDays(today(), -2),
    endDate: addDays(today(), 28),
    originalEndDate: addDays(today(), 28),
    trainingsTotal: 11,
    trainingsLeft: 8,
    freezeLimitDays: 3,
    freeze: null,
    expiredAt: null,
    burnedTrainings: 0,
    notified: { endingSoon: false, lowTrainings: false, expired: false },
    ...fields,
  };
  await seed(`subscriptions/${id}`, data);
  if (data.isCurrent) {
    const user = await read(`users/${clientId}`);
    await seed(`users/${clientId}`, { ...user, currentSubscriptionId: id });
  }
}

/**
 * Тренировка «вручную», начинающаяся через [startsInMs] от сейчас
 * (+ ячейка календаря). Возвращает id.
 */
export async function seedTraining(id, startsInMs, fields = {}) {
  const startMs = Date.now() + startsInMs;
  const wall = new Date(startMs + MSK_MS);
  const date = wall.toISOString().slice(0, 10);
  const startTime = wall.toISOString().slice(11, 16);
  const slot = wall.getUTCHours() < 14 ? 'morning' : 'evening';
  const slotKey = `${date}_${slot}`;
  await seed(`trainings/${id}`, {
    slotKey,
    date,
    slot,
    startTime,
    startAt: Timestamp.fromMillis(startMs),
    durationMinutes: 60,
    capacity: 13,
    bookedCount: 0,
    status: 'scheduled',
    source: 'manual',
    ...fields,
  });
  await seed(`calendar_slots/${slotKey}`, {
    date,
    slot,
    activeTrainingId: id,
    overridesDefault: true,
  });
  return id;
}

/** Причина отказа из ответа функции. */
export const reason = (response) => response.error?.details?.reason;
