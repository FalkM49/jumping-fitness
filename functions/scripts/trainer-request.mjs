// Создать в ЛОКАЛЬНЫХ эмуляторах нового пользователя с заявкой в тренеры —
// чтобы было что одобрять на экране администратора.
//
//   npm run dev:trainer-request -- olga@mail.ru "Ольга Петрова" +79161112233
//
// Путь тот же, что у приложения: вход по почте (подтверждённой) в эмуляторе
// Auth, затем одна запись (batch) профиля и заявки от имени этого
// пользователя — её проверяют настоящие правила Firestore.
// Пароль созданного аккаунта — password123.

import { FIRESTORE, PROJECT_ID, normalizePhone, post, signInVerified } from './dev-auth.mjs';

const [emailArg, fullName = 'Ольга Петрова', phoneArg = '+79161112233'] = process.argv.slice(2);
const email = emailArg?.trim().toLowerCase();
const phone = normalizePhone(phoneArg);
if (!email?.includes('@') || !phone) {
  console.error('Укажите почту и, по желанию, ФИО в кавычках и телефон: olga@mail.ru "Ольга Петрова" +79161112233');
  process.exit(1);
}

// 1. Вход с подтверждённой почтой.
const { idToken, uid } = await signInVerified(email);

// 2. Регистрация: профиль client + заявка pending одним batch, время — серверное.
const documents = `projects/${PROJECT_ID}/databases/(default)/documents`;
const create = (path, fields) => ({
  update: {
    name: `${documents}/${path}`,
    fields: Object.fromEntries(
      Object.entries(fields).map(([k, v]) => [
        k,
        typeof v === 'boolean' ? { booleanValue: v } : { stringValue: v },
      ]),
    ),
  },
  updateTransforms: [{ fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' }],
  currentDocument: { exists: false },
});

await post(
  `http://${FIRESTORE}/v1/${documents}:commit`,
  {
    writes: [
      create(`users/${uid}`, { fullName, phone, role: 'client', isAdmin: false }),
      create(`trainer_requests/${uid}`, { uid, fullName, phone, status: 'pending' }),
    ],
  },
  idToken,
);

console.log(`Готово: ${fullName} (${email}) подал(а) заявку в тренеры.`);
