// Выдать флаг администратора пользователю в ЛОКАЛЬНОМ эмуляторе.
// В настоящем проекте флаг ставится вручную в Firebase Console (ТЗ 2).
//
//   npm run dev:make-admin -- anna@mail.ru
//
// Пользователь должен уже зарегистрироваться в приложении.

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const email = process.argv[2]?.trim().toLowerCase();
if (!email?.includes('@')) {
  console.error('Укажите почту, с которой вы зарегистрировались: anna@mail.ru');
  process.exit(1);
}

// Только эмулятор: без этих переменных Admin SDK пошёл бы в настоящий проект.
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
initializeApp({ projectId: 'demo-jumping-fitness' });

const user = await getAuth().getUserByEmail(email).catch(() => null);
if (!user) {
  console.error(`Пользователь ${email} не найден в эмуляторе Auth.`);
  process.exit(1);
}

const profile = getFirestore().doc(`users/${user.uid}`);
if (!(await profile.get()).exists) {
  console.error(`У ${email} ещё нет профиля: сначала пройдите регистрацию в приложении.`);
  process.exit(1);
}

await profile.update({ isAdmin: true });
console.log(`Готово: ${email} (uid ${user.uid}) — администратор.`);
