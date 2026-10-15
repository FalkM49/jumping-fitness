/**
 * Серверные функции как HTTP API — общая часть для любой площадки.
 *
 * Приложение вызывает функции по протоколу callable-функций Firebase (плагин
 * cloud_functions, `httpsCallableFromUrl`):
 *   POST <адрес API>/bookTraining
 *   Authorization: Bearer <ID-токен Firebase Auth>
 *   { "data": { … } }
 * Ответ: { "result": … } или { "error": { status, message, details } }.
 *
 * Площадки — тонкие адаптеры поверх этого модуля: они только переводят свой
 * формат запроса в ApiRequest и обратно:
 *   yandex.ts   — Yandex Cloud Functions + API Gateway, таймеры;
 *   netlify.ts  — Netlify Functions, Scheduled Functions.
 */
import { getAuth } from 'firebase-admin/auth';
import { logger } from 'firebase-functions';
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

import { WEB_APP_ORIGINS } from './config.js';
import * as api from './index.js';

type Callable = { run(request: CallableRequest<unknown>): unknown };
type Job = { run(event: never): void | Promise<void> };

/** Функции, которые может вызвать приложение. */
export const callables: Record<string, Callable> = {
  bookTraining: api.bookTraining,
  cancelBooking: api.cancelBooking,
  freezeSubscription: api.freezeSubscription,
  ensureMonthlyFlower: api.ensureMonthlyFlower,
  notifyTrainerRequest: api.notifyTrainerRequest,
  reportClientError: api.reportClientError,
  createTraining: api.createTraining,
  updateTraining: api.updateTraining,
  cancelTraining: api.cancelTraining,
  removeClientFromTraining: api.removeClientFromTraining,
  renewSubscription: api.renewSubscription,
  approveTrainerRequest: api.approveTrainerRequest,
  rejectTrainerRequest: api.rejectTrainerRequest,
  runSubscriptionExpiry: api.runSubscriptionExpiry,
};

/** Ночные задачи (по расписанию площадки). */
export const jobs: Record<string, Job> = {
  expireSubscriptionsDaily: api.expireSubscriptionsDaily,
  assignMonthlyFlowers: api.assignMonthlyFlowers,
};

/** Запуск ночной задачи; false — такой задачи нет. Ошибка пробрасывается. */
export async function runJob(name: string): Promise<boolean> {
  const job = jobs[name];
  if (!job) return false;
  await job.run({} as never);
  return true;
}

/** HTTP-запрос, уже извлечённый из формата площадки. */
export interface ApiRequest {
  method: string;
  /** Имя функции — из пути (`/bookTraining`). */
  fn: string;
  /** Имена заголовков — в любом регистре. */
  headers: Record<string, string | undefined>;
  /** Тело запроса как текст (JSON). */
  body: string;
}

export interface ApiResponse {
  statusCode: number;
  headers: Record<string, string>;
  body: string;
}

const json = (statusCode: number, body: unknown): ApiResponse => ({
  statusCode,
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
  body: JSON.stringify(body),
});

const failure = (error: HttpsError) =>
  json(error.httpErrorCode.status, { error: error.toJSON() });

function header(request: ApiRequest, name: string): string | undefined {
  const key = Object.keys(request.headers).find((k) => k.toLowerCase() === name);
  return key ? request.headers[key] : undefined;
}

/**
 * Числа, которые SDK Firebase на телефоне передаёт «обёрнутыми»
 * (64-битные — как { '@type': '…Int64Value', value: '…' }), — в обычные.
 */
export function decode(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(decode);
  if (value !== null && typeof value === 'object') {
    const obj = value as Record<string, unknown>;
    const type = obj['@type'];
    if (
      typeof type === 'string' &&
      /Int64Value$/.test(type) &&
      (typeof obj.value === 'string' || typeof obj.value === 'number')
    ) {
      return Number(obj.value);
    }
    return Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, decode(v)]));
  }
  return value;
}

/**
 * CORS для веб-версии: браузер вызывает функции с другого адреса (Firebase
 * Hosting) и сначала спрашивает разрешение запросом OPTIONS. Разрешаем
 * только адреса приложения и локальную разработку; телефонам (Android)
 * эти заголовки не нужны — у них нет Origin.
 */
function corsHeaders(request: ApiRequest): Record<string, string> {
  const origin = header(request, 'origin');
  if (!origin || !WEB_APP_ORIGINS.some((re) => re.test(origin))) return {};
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers':
      'Authorization, Content-Type, Firebase-Instance-ID-Token, X-Firebase-AppCheck, X-Firebase-GMPID',
    'Access-Control-Max-Age': '3600',
    Vary: 'Origin',
  };
}

export async function handleApiRequest(request: ApiRequest): Promise<ApiResponse> {
  const cors = corsHeaders(request);
  if (request.method.toUpperCase() === 'OPTIONS') {
    return { statusCode: 204, headers: cors, body: '' };
  }
  const response = await callFunction(request);
  return { ...response, headers: { ...response.headers, ...cors } };
}

async function callFunction(request: ApiRequest): Promise<ApiResponse> {
  const name = request.fn;
  const fn = Object.hasOwn(callables, name) ? callables[name] : undefined;
  if (!fn) {
    return failure(new HttpsError('not-found', `Функция «${name}» не найдена.`));
  }
  if (request.method.toUpperCase() !== 'POST') {
    return failure(new HttpsError('invalid-argument', 'Нужен POST-запрос.'));
  }

  let data: unknown;
  try {
    const parsed = request.body ? (JSON.parse(request.body) as { data?: unknown }) : {};
    data = decode(parsed?.data ?? null);
  } catch {
    return failure(new HttpsError('invalid-argument', 'Некорректный запрос.'));
  }

  // Вход: ID-токен Firebase Auth. Нет токена — функция сама ответит
  // «нужно войти»; неверный или просроченный — отказ сразу.
  let auth: CallableRequest<unknown>['auth'];
  const bearer = header(request, 'authorization')?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (bearer) {
    try {
      const token = await getAuth().verifyIdToken(bearer);
      auth = { uid: token.uid, token, rawToken: bearer };
    } catch (error) {
      logger.info('Токен входа не принят', {
        fn: name,
        code: (error as { code?: string }).code ?? String(error),
      });
      return failure(new HttpsError('unauthenticated', 'Вход устарел. Войдите в приложение заново.'));
    }
  }

  try {
    const result = await fn.run({
      data,
      auth,
      rawRequest: undefined as never,
      acceptsStreaming: false,
    });
    return json(200, { result: result ?? null });
  } catch (error) {
    if (error instanceof HttpsError) return failure(error);
    logger.error(`Функция ${name} упала`, error);
    return failure(new HttpsError('internal', 'Внутренняя ошибка сервера. Попробуйте позже.'));
  }
}
