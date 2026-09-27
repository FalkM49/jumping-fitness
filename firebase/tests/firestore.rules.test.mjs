// Тесты Firestore Security Rules.
// Запуск (нужны Node 20+ и Java 11+):
//   cd firebase/tests && npm install && npm test
// Эмулятор поднимается и гасится автоматически, в интернет ничего не уходит
// (проект с префиксом demo- работает полностью офлайн).

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const PROJECT_ID = 'demo-jumping-fitness';

const PHONES = {
  anna: '+79990000001',
  olga: '+79990000002',
  maria: '+79990000003',
  dev: '+79990000004',
  newbie: '+79990000005',
};

/** @type {import('@firebase/rules-unit-testing').RulesTestEnvironment} */
let env;

// Контексты: кто делает запрос. Вход — по почте, подтверждённой по ссылке.
const as = (uid) =>
  env.authenticatedContext(uid, { email: `${uid}@test.ru`, email_verified: true }).firestore();
// Вошёл, но ещё не открыл ссылку из письма.
const unverified = (uid) =>
  env.authenticatedContext(uid, { email: `${uid}@test.ru`, email_verified: false }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => {
  await env?.cleanup();
});

// Перед каждым тестом — чистая база с одинаковыми данными.
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const now = Timestamp.now();
    const user = (name, phone, role, isAdmin = false) => ({
      fullName: name, phone, role, isAdmin, createdAt: now,
    });

    await setDoc(doc(db, 'users/anna'), user('Анна Смирнова', PHONES.anna, 'client'));
    await setDoc(doc(db, 'users/olga'), user('Ольга Петрова', PHONES.olga, 'client'));
    await setDoc(doc(db, 'users/maria'), user('Мария Ковалёва', PHONES.maria, 'trainer'));
    // Админ-разработчик: роль client, но флаг isAdmin.
    await setDoc(doc(db, 'users/dev'), user('Разработчик', PHONES.dev, 'client', true));

    await setDoc(doc(db, 'trainer_requests/olga'), {
      uid: 'olga', fullName: 'Ольга Петрова', phone: PHONES.olga,
      status: 'pending', createdAt: now,
    });

    const start = Timestamp.fromDate(new Date('2026-09-28T05:10:00Z'));
    await setDoc(doc(db, 'calendar_slots/2026-09-28_morning'), {
      date: '2026-09-28', slot: 'morning', activeTrainingId: 't1', overridesDefault: true,
    });
    await setDoc(doc(db, 'trainings/t1'), {
      slotKey: '2026-09-28_morning', date: '2026-09-28', slot: 'morning',
      startTime: '08:10', startAt: start, durationMinutes: 60,
      capacity: 13, bookedCount: 2, status: 'scheduled', source: 'default',
    });
    for (const [uid, name] of [['anna', 'Анна Смирнова'], ['olga', 'Ольга Петрова']]) {
      await setDoc(doc(db, `trainings/t1/bookings/${uid}`), {
        clientId: uid, clientName: name, status: 'active',
        trainingId: 't1', trainingStartAt: start, subscriptionId: `sub_${uid}`,
      });
    }

    for (const uid of ['anna', 'olga']) {
      await setDoc(doc(db, `subscriptions/sub_${uid}`), {
        clientId: uid, isCurrent: true, startDate: '2026-09-01', endDate: '2026-09-30',
        trainingsTotal: 11, trainingsLeft: 8,
      });
    }

    await setDoc(doc(db, 'flowers/peony'), { name: 'Пион', order: 1 });
    await setDoc(doc(db, 'settings/defaults'), { timezone: 'Europe/Moscow' });
  });
});

// Корректный документ профиля при регистрации.
const newProfile = (overrides = {}) => ({
  fullName: 'Новая Клиентка',
  phone: PHONES.newbie,
  role: 'client',
  isAdmin: false,
  createdAt: serverTimestamp(),
  ...overrides,
});

// ============================================================================
describe('users', () => {
  it('без входа ничего не читается', async () => {
    await assertFails(getDoc(doc(anon(), 'users/anna')));
  });

  it('клиент читает свой профиль, но не чужой', async () => {
    await assertSucceeds(getDoc(doc(as('anna'), 'users/anna')));
    await assertFails(getDoc(doc(as('anna'), 'users/olga')));
    await assertFails(getDoc(doc(as('anna'), 'users/maria')));
  });

  it('клиент не может получить список пользователей', async () => {
    await assertFails(getDocs(collection(as('anna'), 'users')));
  });

  it('тренер и админ видят всех', async () => {
    await assertSucceeds(getDocs(collection(as('maria'), 'users')));
    await assertSucceeds(getDoc(doc(as('dev'), 'users/anna')));
  });

  it('ещё не зарегистрированный может проверить свой профиль', async () => {
    await assertSucceeds(getDoc(doc(as('newbie'), 'users/newbie')));
  });

  it('регистрация: свой профиль с ролью client — можно', async () => {
    await assertSucceeds(setDoc(doc(as('newbie'), 'users/newbie'), newProfile()));
  });

  it('регистрация: нельзя назначить себе тренера или админа', async () => {
    await assertFails(setDoc(doc(as('newbie'), 'users/newbie'), newProfile({ role: 'trainer' })));
    await assertFails(setDoc(doc(as('newbie'), 'users/newbie'), newProfile({ role: 'admin' })));
    await assertFails(setDoc(doc(as('newbie'), 'users/newbie'), newProfile({ isAdmin: true })));
  });

  it('регистрация: телефон — только в формате E.164', async () => {
    for (const phone of ['89991234567', '+7 999 123-45-67', '+0123456789', '+7999', 79991234567, '']) {
      await assertFails(setDoc(doc(as('newbie'), 'users/newbie'), newProfile({ phone })));
    }
    await assertSucceeds(setDoc(doc(as('newbie'), 'users/newbie'), newProfile({ phone: '+375291234567' })));
  });

  it('неподтверждённая почта: ни регистрации, ни чтения', async () => {
    await assertFails(setDoc(doc(unverified('newbie'), 'users/newbie'), newProfile()));
    await assertFails(getDoc(doc(unverified('newbie'), 'users/newbie')));
    await assertFails(getDoc(doc(unverified('anna'), 'users/anna')));
    await assertFails(getDoc(doc(unverified('anna'), 'trainings/t1')));
  });

  it('регистрация: нельзя создать профиль за другого', async () => {
    await assertFails(setDoc(doc(as('newbie'), 'users/someone'), newProfile()));
  });

  it('регистрация: лишние поля и клиентское время запрещены', async () => {
    await assertFails(setDoc(doc(as('newbie'), 'users/newbie'),
      newProfile({ currentSubscriptionId: 'free' })));
    await assertFails(setDoc(doc(as('newbie'), 'users/newbie'),
      newProfile({ createdAt: Timestamp.fromDate(new Date('2020-01-01')) })));
  });

  it('регистрация: пустое или слишком короткое ФИО запрещено', async () => {
    await assertFails(setDoc(doc(as('newbie'), 'users/newbie'), newProfile({ fullName: 'Я' })));
    await assertFails(setDoc(doc(as('newbie'), 'users/newbie'), newProfile({ fullName: '  Анна' })));
  });

  it('регистрация: пробелы по краям не прячутся за переводом строки', async () => {
    await assertFails(setDoc(doc(as('newbie'), 'users/newbie'), newProfile({ fullName: ' Анна\nБ' })));
    await assertFails(setDoc(doc(as('newbie'), 'users/newbie'), newProfile({ fullName: 'Анна\nБВ ' })));
  });

  it('регистрация: управляющие символы в ФИО запрещены', async () => {
    await assertFails(setDoc(doc(as('newbie'), 'users/newbie'), newProfile({ fullName: 'Анна\nСмирнова' })));
    await assertFails(setDoc(doc(as('newbie'), 'users/newbie'), newProfile({ fullName: 'Анна\tСмирнова' })));
    await assertSucceeds(setDoc(doc(as('newbie'), 'users/newbie'), newProfile({ fullName: 'Анна-Мария Ёлкина' })));
  });

  it('клиент не может поменять себе роль, флаг админа или удалить профиль', async () => {
    await assertFails(updateDoc(doc(as('anna'), 'users/anna'), { role: 'trainer' }));
    await assertFails(updateDoc(doc(as('anna'), 'users/anna'), { isAdmin: true }));
    await assertFails(updateDoc(doc(as('anna'), 'users/anna'), { fullName: 'Другое Имя' }));
    await assertFails(deleteDoc(doc(as('anna'), 'users/anna')));
  });

  it('тренер тоже не пишет в профили напрямую', async () => {
    await assertFails(updateDoc(doc(as('maria'), 'users/anna'), { role: 'trainer' }));
  });
});

// ============================================================================
describe('users/{uid}/notifications', () => {
  const seedNotification = () =>
    env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'users/anna/notifications/n1'), {
        kind: 'training_changed', title: 'Т', body: 'Б', data: {}, read: false,
        createdAt: Timestamp.now(),
      }));

  it('свои уведомления видно и можно отметить прочитанными', async () => {
    await seedNotification();
    await assertSucceeds(getDocs(collection(as('anna'), 'users/anna/notifications')));
    await assertSucceeds(updateDoc(doc(as('anna'), 'users/anna/notifications/n1'), { read: true }));
  });

  it('чужие не видно; менять текст, создавать и удалять нельзя', async () => {
    await seedNotification();
    await assertFails(getDocs(collection(as('olga'), 'users/anna/notifications')));
    await assertFails(updateDoc(doc(as('anna'), 'users/anna/notifications/n1'), { title: 'Подделка' }));
    await assertFails(updateDoc(doc(as('anna'), 'users/anna/notifications/n1'), { read: false }));
    await assertFails(setDoc(doc(as('anna'), 'users/anna/notifications/n2'), { title: 'x', read: false }));
    await assertFails(deleteDoc(doc(as('anna'), 'users/anna/notifications/n1')));
  });
});

describe('users/{uid}/devices', () => {
  const device = (overrides = {}) => ({
    token: 'fcm-token-123', platform: 'android', updatedAt: serverTimestamp(), ...overrides,
  });

  it('свой токен устройства сохранить можно — телефон и браузер', async () => {
    await assertSucceeds(setDoc(doc(as('anna'), 'users/anna/devices/phone1'), device()));
    await assertSucceeds(setDoc(doc(as('anna'), 'users/anna/devices/iphone-web'), device({ platform: 'web' })));
  });

  it('чужой — нельзя', async () => {
    await assertFails(setDoc(doc(as('anna'), 'users/olga/devices/phone1'), device()));
    await assertFails(getDoc(doc(as('anna'), 'users/olga/devices/phone1')));
  });

  it('некорректная платформа или лишние поля — нельзя', async () => {
    await assertFails(setDoc(doc(as('anna'), 'users/anna/devices/p'), device({ platform: 'windows' })));
    await assertFails(setDoc(doc(as('anna'), 'users/anna/devices/p'), device({ role: 'trainer' })));
  });
});

// ============================================================================
describe('trainer_requests', () => {
  const request = (overrides = {}) => ({
    uid: 'newbie', fullName: 'Новая Клиентка', phone: PHONES.newbie,
    status: 'pending', createdAt: serverTimestamp(), ...overrides,
  });

  it('при регистрации можно одним batch создать профиль и заявку', async () => {
    const db = as('newbie');
    const batch = writeBatch(db);
    batch.set(doc(db, 'users/newbie'), newProfile());
    batch.set(doc(db, 'trainer_requests/newbie'), request());
    await assertSucceeds(batch.commit());
  });

  it('заявка без профиля — нельзя', async () => {
    await assertFails(setDoc(doc(as('newbie'), 'trainer_requests/newbie'), request()));
  });

  it('нельзя подать заявку сразу одобренной', async () => {
    const db = as('newbie');
    const batch = writeBatch(db);
    batch.set(doc(db, 'users/newbie'), newProfile());
    batch.set(doc(db, 'trainer_requests/newbie'), request({ status: 'approved' }));
    await assertFails(batch.commit());
  });

  it('нельзя подать заявку за другого', async () => {
    await assertFails(setDoc(doc(as('anna'), 'trainer_requests/olga'),
      request({ uid: 'olga', fullName: 'Ольга Петрова', phone: PHONES.olga })));
  });

  it('ФИО и телефон в заявке должны совпадать с профилем', async () => {
    await assertFails(setDoc(doc(as('anna'), 'trainer_requests/anna'),
      request({ uid: 'anna', fullName: 'Кто-то Другой', phone: PHONES.anna })));
    await assertFails(setDoc(doc(as('anna'), 'trainer_requests/anna'),
      request({ uid: 'anna', fullName: 'Анна Смирнова', phone: PHONES.olga })));
    await assertSucceeds(setDoc(doc(as('anna'), 'trainer_requests/anna'),
      request({ uid: 'anna', fullName: 'Анна Смирнова', phone: PHONES.anna })));
  });

  it('повторная заявка поверх существующей — нельзя', async () => {
    await assertFails(setDoc(doc(as('olga'), 'trainer_requests/olga'),
      request({ uid: 'olga', fullName: 'Ольга Петрова', phone: PHONES.olga })));
  });

  it('тренер заявку не подаёт', async () => {
    await assertFails(setDoc(doc(as('maria'), 'trainer_requests/maria'),
      request({ uid: 'maria', fullName: 'Мария Ковалёва', phone: PHONES.maria })));
  });

  it('админ заявку не подаёт', async () => {
    await assertFails(setDoc(doc(as('dev'), 'trainer_requests/dev'),
      request({ uid: 'dev', fullName: 'Разработчик', phone: PHONES.dev })));
  });

  it('свою заявку видно, чужую — нет; список — только админу', async () => {
    await assertSucceeds(getDoc(doc(as('olga'), 'trainer_requests/olga')));
    await assertFails(getDoc(doc(as('anna'), 'trainer_requests/olga')));
    await assertFails(getDocs(collection(as('maria'), 'trainer_requests')));
    await assertSucceeds(getDocs(collection(as('dev'), 'trainer_requests')));
  });

  it('одобрить напрямую не может никто — только функция', async () => {
    await assertFails(updateDoc(doc(as('olga'), 'trainer_requests/olga'), { status: 'approved' }));
    await assertFails(updateDoc(doc(as('dev'), 'trainer_requests/olga'), { status: 'approved' }));
  });
});

// ============================================================================
describe('trainings и calendar_slots', () => {
  it('календарь читают все зарегистрированные', async () => {
    await assertSucceeds(getDoc(doc(as('anna'), 'trainings/t1')));
    await assertSucceeds(getDocs(collection(as('anna'), 'trainings')));
    await assertSucceeds(getDoc(doc(as('anna'), 'calendar_slots/2026-09-28_morning')));
  });

  it('без профиля или без входа календарь не виден', async () => {
    await assertFails(getDoc(doc(as('newbie'), 'trainings/t1')));
    await assertFails(getDoc(doc(anon(), 'trainings/t1')));
  });

  it('клиент не может накрутить места', async () => {
    await assertFails(updateDoc(doc(as('anna'), 'trainings/t1'), { capacity: 50 }));
    await assertFails(updateDoc(doc(as('anna'), 'trainings/t1'), { bookedCount: 0 }));
  });

  it('тренер меняет календарь только через функции', async () => {
    await assertFails(updateDoc(doc(as('maria'), 'trainings/t1'), { startTime: '09:00' }));
    await assertFails(setDoc(doc(as('maria'), 'trainings/new'), { status: 'scheduled' }));
    await assertFails(setDoc(doc(as('maria'), 'calendar_slots/x'), { activeTrainingId: null }));
  });
});

// ============================================================================
describe('bookings', () => {
  it('клиент видит свою запись, но не чужую', async () => {
    await assertSucceeds(getDoc(doc(as('anna'), 'trainings/t1/bookings/anna')));
    await assertFails(getDoc(doc(as('anna'), 'trainings/t1/bookings/olga')));
  });

  it('клиент не видит список записавшихся', async () => {
    await assertFails(getDocs(collection(as('anna'), 'trainings/t1/bookings')));
  });

  it('тренер видит всех записавшихся', async () => {
    await assertSucceeds(getDocs(collection(as('maria'), 'trainings/t1/bookings')));
  });

  it('«мои записи» (collection group) — только со своим фильтром', async () => {
    const db = as('anna');
    await assertSucceeds(getDocs(query(collectionGroup(db, 'bookings'), where('clientId', '==', 'anna'))));
    await assertFails(getDocs(query(collectionGroup(db, 'bookings'), where('clientId', '==', 'olga'))));
    await assertFails(getDocs(collectionGroup(db, 'bookings')));
  });

  it('записаться или отменить напрямую нельзя — только функция', async () => {
    await assertFails(setDoc(doc(as('newbie'), 'trainings/t1/bookings/newbie'), { clientId: 'newbie' }));
    await assertFails(setDoc(doc(as('anna'), 'trainings/t1/bookings/anna'), { clientId: 'anna', status: 'active' }));
    await assertFails(deleteDoc(doc(as('anna'), 'trainings/t1/bookings/anna')));
    await assertFails(deleteDoc(doc(as('maria'), 'trainings/t1/bookings/olga')));
  });
});

// ============================================================================
describe('subscriptions', () => {
  it('клиент видит только свои абонементы', async () => {
    const db = as('anna');
    await assertSucceeds(getDoc(doc(db, 'subscriptions/sub_anna')));
    await assertSucceeds(getDocs(query(collection(db, 'subscriptions'), where('clientId', '==', 'anna'))));
    await assertFails(getDoc(doc(db, 'subscriptions/sub_olga')));
    await assertFails(getDocs(collection(db, 'subscriptions')));
  });

  it('тренер и админ видят все абонементы', async () => {
    await assertSucceeds(getDocs(collection(as('maria'), 'subscriptions')));
    await assertSucceeds(getDocs(collection(as('dev'), 'subscriptions')));
  });

  it('клиент не может накрутить себе тренировки или дни', async () => {
    await assertFails(updateDoc(doc(as('anna'), 'subscriptions/sub_anna'), { trainingsLeft: 99 }));
    await assertFails(updateDoc(doc(as('anna'), 'subscriptions/sub_anna'), { endDate: '2030-01-01' }));
    await assertFails(setDoc(doc(as('anna'), 'subscriptions/free'), { clientId: 'anna', trainingsLeft: 99 }));
  });

  it('тренер продлевает только через функцию', async () => {
    await assertFails(updateDoc(doc(as('maria'), 'subscriptions/sub_anna'), { trainingsLeft: 11 }));
  });
});

// ============================================================================
describe('flowers и settings', () => {
  it('читают зарегистрированные, пишет никто', async () => {
    await assertSucceeds(getDoc(doc(as('anna'), 'flowers/peony')));
    await assertSucceeds(getDoc(doc(as('anna'), 'settings/defaults')));
    await assertFails(setDoc(doc(as('dev'), 'flowers/rose'), { name: 'Роза' }));
    await assertFails(updateDoc(doc(as('maria'), 'settings/defaults'), { timezone: 'UTC' }));
    await assertFails(getDoc(doc(as('newbie'), 'flowers/peony')));
  });
});

// ============================================================================
describe('всё остальное', () => {
  it('неописанные коллекции закрыты', async () => {
    await assertFails(getDoc(doc(as('dev'), 'secrets/x')));
    await assertFails(setDoc(doc(as('dev'), 'secrets/x'), { a: 1 }));
  });
});
