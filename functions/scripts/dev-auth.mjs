// Общее для скриптов ЛОКАЛЬНОЙ разработки: вход в эмуляторе Auth по почте.

export const PROJECT_ID = 'demo-jumping-fitness';
export const AUTH = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
export const FIRESTORE = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';

/** Пароль учётных записей, которые создают скрипты. */
export const DEV_PASSWORD = 'password123';

const identity = `http://${AUTH}/identitytoolkit.googleapis.com/v1`;

export async function post(url, body, token) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  }).catch(() => null);
  if (!response) {
    console.error('Эмуляторы не отвечают. Запустите: npm run emulators');
    process.exit(1);
  }
  const json = await response.json();
  if (!response.ok) {
    console.error(`Ошибка ${response.status}: ${JSON.stringify(json.error ?? json)}`);
    process.exit(1);
  }
  return json;
}

/**
 * Аккаунт с подтверждённой почтой: создаёт (или находит) и входит.
 * Подтверждение ставится правами эмулятора — как будто человек открыл
 * ссылку из письма. Возвращает { uid, idToken } с email_verified в токене.
 */
export async function signInVerified(email, password = DEV_PASSWORD) {
  const lookup = await fetch(`${identity}/accounts:signInWithPassword?key=demo`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  }).catch(() => null);
  if (!lookup) {
    console.error('Эмуляторы не отвечают. Запустите: npm run emulators');
    process.exit(1);
  }
  let uid;
  if (lookup.ok) {
    uid = (await lookup.json()).localId;
  } else {
    ({ localId: uid } = await post(`${identity}/accounts:signUp?key=demo`, {
      email,
      password,
      returnSecureToken: true,
    }));
  }
  await post(
    `${identity}/projects/${PROJECT_ID}/accounts:update`,
    { localId: uid, emailVerified: true },
    'owner',
  );
  const { idToken } = await post(`${identity}/accounts:signInWithPassword?key=demo`, {
    email,
    password,
    returnSecureToken: true,
  });
  return { uid, idToken };
}

/** Найти пользователя по почте в эмуляторе. */
export async function uidByEmail(email) {
  const { users = [] } = await post(
    `${identity}/projects/${PROJECT_ID}/accounts:lookup`,
    { email: [email] },
    'owner',
  );
  return users[0]?.localId ?? null;
}

/** Телефон в E.164, как его сохраняет приложение. */
export function normalizePhone(input) {
  const digits = String(input ?? '').replace(/\D/g, '');
  if (digits.length === 10) return `+7${digits}`;
  if (digits.length === 11 && /^[78]/.test(digits)) return `+7${digits.slice(1)}`;
  return null;
}
