import { logger } from 'firebase-functions';
import { onCall } from 'firebase-functions/v2/https';

import { REGION } from './config.js';

/**
 * Журнал ошибок приложения (веб-версия на iPhone, docs/09, шаг 1).
 *
 * В Safari без Mac консоль не посмотреть, поэтому приложение само присылает
 * необработанные ошибки, сбои вызовов функций и признаки перезагрузки вкладки
 * из-за нехватки памяти. Всё уходит в журнал функции (Yandex Cloud → Логи),
 * в Firestore ничего не пишется.
 */

const KINDS = new Set([
  'flutter_error',
  'zone_error',
  'function_error',
  'unexpected_reload',
  'webgl_lost',
]);

const MAX_TEXT = 4096;
/** Не больше LIMIT отчётов за WINDOW_MS на пользователя (вход — по uid). */
const LIMIT = 20;
const WINDOW_MS = 60_000;

/** Счётчик в памяти экземпляра функции: для защиты от «шторма» хватает. */
const windows = new Map<string, { start: number; count: number }>();

/** `true` — отчёт можно записать; `false` — лимит на эту минуту исчерпан. */
export function allowReport(key: string, now = Date.now()): boolean {
  const current = windows.get(key);
  if (!current || now - current.start >= WINDOW_MS) {
    windows.set(key, { start: now, count: 1 });
    if (windows.size > 10_000) windows.clear();
    return true;
  }
  current.count++;
  return current.count <= LIMIT;
}

const text = (value: unknown): string | undefined =>
  typeof value === 'string' ? value.slice(0, MAX_TEXT) : undefined;

export const reportClientError = onCall({ region: REGION }, (request) => {
  const data =
    request.data !== null && typeof request.data === 'object' && !Array.isArray(request.data)
      ? (request.data as Record<string, unknown>)
      : {};
  const uid = request.auth?.uid;
  // Без входа — общий счётчик: ошибки на экране входа тоже важны.
  if (!allowReport(uid ?? 'anonymous')) return { logged: false };

  const kind = typeof data.kind === 'string' && KINDS.has(data.kind) ? data.kind : 'unknown';
  logger.warn(`Ошибка в приложении: ${kind}`, {
    clientError: true,
    kind,
    uid: uid ?? null,
    // Не «message»: это поле занято заголовком записи в журнале.
    errorMessage: text(data.message),
    stack: text(data.stack),
    route: text(data.route),
    userAgent: text(data.userAgent),
    standalone: data.standalone === true,
    appVersion: text(data.appVersion),
  });
  return { logged: true };
});
