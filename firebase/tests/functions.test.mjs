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
