/**
 * Адаптер Netlify Functions — то же HTTP API (http_api.ts), что и в Yandex.
 *
 * Сами функции Netlify — файлы в functions/netlify/functions/ (Netlify
 * находит их по папке и читает оттуда `config`), они лишь подключают
 * обработчики отсюда:
 *   api.mjs              POST https://<сайт>.netlify.app/api/bookTraining
 *   expire-daily.mjs     ночная задача expireSubscriptionsDaily
 *   flowers-daily.mjs    ночная задача assignMonthlyFlowers
 * Доступ к Firebase — ключ сервисного аккаунта в переменной окружения
 * FIREBASE_SERVICE_ACCOUNT (Netlify → Site configuration → Environment
 * variables), как и в Yandex (index.ts).
 */
import { logger } from 'firebase-functions';

import { handleApiRequest, runJob } from './http_api.js';

/** Из `context` Netlify нужны только параметры пути (`/api/:fn`). */
interface NetlifyContext {
  params?: Record<string, string | undefined>;
}

/** Обработчик вызовов приложения: Web Request → Response. */
export async function apiHandler(req: Request, context?: NetlifyContext): Promise<Response> {
  const fn =
    context?.params?.fn ?? new URL(req.url).pathname.split('/').filter(Boolean).at(-1) ?? '';
  const response = await handleApiRequest({
    method: req.method,
    fn,
    headers: Object.fromEntries(req.headers),
    body: await req.text(),
  });
  return new Response(response.statusCode === 204 ? null : response.body, {
    status: response.statusCode,
    headers: response.headers,
  });
}

/**
 * Обработчик ночной задачи по расписанию (Scheduled Functions). Ошибка
 * пробрасывается — Netlify отметит запуск неудачным в журнале функции.
 */
export function scheduledJob(name: string): () => Promise<void> {
  return async () => {
    if (!(await runJob(name))) throw new Error(`Неизвестная задача ${name}`);
    logger.info('Ночная задача выполнена', { job: name });
  };
}
