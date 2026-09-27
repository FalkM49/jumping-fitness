// Загрузка справочников: 14 цветков (ТЗ 12) и settings/defaults (ТЗ 7).
//
// Локальный эмулятор:
//   npm run dev:seed
//
// Настоящий проект (один раз при развёртывании, этап 8):
//   npm run seed -- --project <id-проекта> --key <путь-к-ключу.json>
// Ключ сервисного аккаунта: Firebase Console → Настройки проекта →
// Сервисные аккаунты → «Создать закрытый ключ». Храните его в секрете
// и удалите после загрузки.
//
// Цветки перезаписываются (это справочник). settings/defaults создаётся,
// только если его ещё нет, — чтобы не затереть значения, которые
// администратор поменял в Console; перезаписать: --force-settings.

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { applicationDefault, cert, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const args = process.argv.slice(2);
const option = (name) => {
  const i = args.indexOf(name);
  return i === -1 ? undefined : args[i + 1];
};
const project = option('--project');
const key = option('--key');
const forceSettings = args.includes('--force-settings');

if (project) {
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    console.error('Задан FIRESTORE_EMULATOR_HOST — для настоящего проекта уберите его.');
    process.exit(1);
  }
  initializeApp({
    projectId: project,
    credential: key ? cert(JSON.parse(readFileSync(resolve(key), 'utf8'))) : applicationDefault(),
  });
} else {
  process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
  initializeApp({ projectId: 'demo-jumping-fitness' });
}
const db = getFirestore();

const seedFile = (name) =>
  JSON.parse(readFileSync(new URL(`../../firebase/seed/${name}`, import.meta.url), 'utf8'));

const batch = db.batch();
const flowers = seedFile('flowers.json');
for (const { id, ...flower } of flowers) {
  batch.set(db.doc(`flowers/${id}`), flower);
}
const settingsRef = db.doc('settings/defaults');
const settingsExist = (await settingsRef.get()).exists;
if (!settingsExist || forceSettings) {
  batch.set(settingsRef, seedFile('settings_defaults.json'));
}
await batch.commit();

const where = project ? `проект ${project}` : 'локальный эмулятор';
console.log(`Готово (${where}): цветков — ${flowers.length}.`);
console.log(
  settingsExist && !forceSettings
    ? 'settings/defaults уже был — оставлен как есть (перезаписать: --force-settings).'
    : 'settings/defaults записан.',
);
