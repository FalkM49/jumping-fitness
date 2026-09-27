// Показать письма, которые «отправил» эмулятор Firebase Auth: ссылки для
// подтверждения почты и сброса пароля. Настоящих писем эмулятор не шлёт —
// откройте ссылку в браузере на этом компьютере, и действие выполнится.
//
//   npm run dev:links
//
// Работает только с локальным эмулятором (проект demo-jumping-fitness).

import { AUTH, PROJECT_ID } from './dev-auth.mjs';

const response = await fetch(
  `http://${AUTH}/emulator/v1/projects/${PROJECT_ID}/oobCodes`,
).catch(() => null);

if (!response?.ok) {
  console.error(`Эмулятор Auth не отвечает на ${AUTH}. Запустите: npm run emulators`);
  process.exit(1);
}

const kinds = { VERIFY_EMAIL: 'подтверждение почты', PASSWORD_RESET: 'сброс пароля' };
const { oobCodes = [] } = await response.json();
if (oobCodes.length === 0) {
  console.log('Писем пока нет: зарегистрируйтесь или нажмите «Забыли пароль?» в приложении.');
} else {
  for (const { email, requestType, oobLink } of oobCodes) {
    console.log(`${email} — ${kinds[requestType] ?? requestType}:\n  ${oobLink}\n`);
  }
}
