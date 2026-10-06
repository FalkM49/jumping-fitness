// Тесты заявок в тренеры (Cloud Functions) на локальных эмуляторах.
// Запуск: cd firebase/tests && npm run test:functions
// Функции вызываются так же, как их вызывает приложение: HTTPS-запрос
// с ID-токеном пользователя из эмулятора Auth.

import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  Timestamp,
  call as callAs,
  clearDb,
  read,
  seed,
  signUp,
  startEnv,
  stopEnv,
} from './helpers.mjs';

const call = (name, data, idToken) => callAs(name, data, idToken && { idToken });
const profile = (role, isAdmin = false) => ({
  fullName: 'Тестовый Пользователь',
  phone: '+79990000000',
  role,
  isAdmin,
  createdAt: Timestamp.now(),
});

const pendingRequest = (uid) => ({
  uid,
  fullName: 'Тестовый Пользователь',
  phone: '+79990000000',
  status: 'pending',
  createdAt: Timestamp.now(),
});

let admin, applicant, trainer;

before(async () => {
  await startEnv();
  [admin, applicant, trainer] = await Promise.all([signUp(), signUp(), signUp()]);
});

after(async () => {
  await stopEnv();
});

beforeEach(async () => {
  await clearDb();
  await seed(`users/${admin.uid}`, profile('client', true));
  await seed(`users/${trainer.uid}`, profile('trainer'));
  await seed(`users/${applicant.uid}`, profile('client'));
  await seed(`trainer_requests/${applicant.uid}`, pendingRequest(applicant.uid));
});

describe('approveTrainerRequest', () => {
  it('админ одобряет: заявка approved, роль trainer, отмечено кто и когда', async () => {
    const response = await call('approveTrainerRequest', { uid: applicant.uid }, admin.idToken);
    assert.deepEqual(response.result, { uid: applicant.uid, status: 'approved' });

    const request = await read(`trainer_requests/${applicant.uid}`);
    assert.equal(request.status, 'approved');
    assert.equal(request.decidedBy, admin.uid);
    assert.ok(request.decidedAt instanceof Timestamp);
    assert.equal((await read(`users/${applicant.uid}`)).role, 'trainer');
  });

  it('клиент и тренер без флага админа — отказ, ничего не меняется', async () => {
    for (const caller of [applicant, trainer]) {
      const response = await call('approveTrainerRequest', { uid: applicant.uid }, caller.idToken);
      assert.equal(response.error?.status, 'PERMISSION_DENIED');
    }
    assert.equal((await read(`trainer_requests/${applicant.uid}`)).status, 'pending');
    assert.equal((await read(`users/${applicant.uid}`)).role, 'client');
  });

  it('без входа — отказ', async () => {
    const response = await call('approveTrainerRequest', { uid: applicant.uid });
    assert.equal(response.error?.status, 'UNAUTHENTICATED');
  });

  it('уже рассмотренную заявку повторно не решить', async () => {
    await call('rejectTrainerRequest', { uid: applicant.uid }, admin.idToken);
    const response = await call('approveTrainerRequest', { uid: applicant.uid }, admin.idToken);
    assert.equal(response.error?.status, 'FAILED_PRECONDITION');
    assert.equal((await read(`users/${applicant.uid}`)).role, 'client');
  });

  it('нет заявки — not-found; нет профиля — не одобряется', async () => {
    let response = await call('approveTrainerRequest', { uid: trainer.uid }, admin.idToken);
    assert.equal(response.error?.status, 'NOT_FOUND');

    await seed(`trainer_requests/ghost`, pendingRequest('ghost'));
    response = await call('approveTrainerRequest', { uid: 'ghost' }, admin.idToken);
    assert.equal(response.error?.status, 'FAILED_PRECONDITION');
    assert.equal((await read('trainer_requests/ghost')).status, 'pending');
  });

  it('кривые аргументы — invalid-argument', async () => {
    for (const data of [null, {}, { uid: '' }, { uid: 42 }, { uid: 'a/b' }]) {
      const response = await call('approveTrainerRequest', data, admin.idToken);
      assert.equal(response.error?.status, 'INVALID_ARGUMENT', JSON.stringify(data));
    }
  });
});

describe('rejectTrainerRequest', () => {
  it('админ отклоняет: заявка rejected, роль остаётся client', async () => {
    const response = await call('rejectTrainerRequest', { uid: applicant.uid }, admin.idToken);
    assert.deepEqual(response.result, { uid: applicant.uid, status: 'rejected' });

    const request = await read(`trainer_requests/${applicant.uid}`);
    assert.equal(request.status, 'rejected');
    assert.equal(request.decidedBy, admin.uid);
    assert.equal((await read(`users/${applicant.uid}`)).role, 'client');
  });

  it('не админ — отказ', async () => {
    const response = await call('rejectTrainerRequest', { uid: applicant.uid }, trainer.idToken);
    assert.equal(response.error?.status, 'PERMISSION_DENIED');
    assert.equal((await read(`trainer_requests/${applicant.uid}`)).status, 'pending');
  });
});

describe('reportClientError — журнал ошибок приложения', () => {
  const report = (overrides = {}) => ({
    kind: 'function_error',
    message: 'TypeError: x',
    stack: 'at main.dart.js:1',
    route: '/',
    userAgent: 'iPhone',
    standalone: true,
    appVersion: '0.1.0+1',
    ...overrides,
  });

  it('принимает отчёт с входом и без; длинный текст и неизвестный тип не ломают вызов', async () => {
    const first = await call('reportClientError', report(), trainer.idToken);
    assert.deepEqual(first.result, { logged: true }, JSON.stringify(first));
    const anonymous = await call('reportClientError', report());
    assert.deepEqual(anonymous.result, { logged: true }, JSON.stringify(anonymous));
    const odd = await call('reportClientError', report({ kind: 'что-то', message: 'x'.repeat(10_000) }), trainer.idToken);
    assert.deepEqual(odd.result, { logged: true });
    assert.deepEqual((await call('reportClientError', null, trainer.idToken)).result, { logged: true });
  });

  // Счётчик живёт в памяти экземпляра функции (эмулятор может запускать
  // её в разных процессах), поэтому проверяем сам счётчик.
  it('не больше 20 отчётов в минуту от одного пользователя', async () => {
    const { allowReport } = await import('../../functions/lib/client_errors.js');
    const t0 = 1_000_000;
    const results = Array.from({ length: 25 }, (_, i) => allowReport('u-limit', t0 + i));
    assert.equal(results.filter(Boolean).length, 20);
    assert.equal(allowReport('другой', t0), true, 'у другого пользователя свой счётчик');
    assert.equal(allowReport('u-limit', t0 + 60_000), true, 'через минуту — снова можно');
  });
});
