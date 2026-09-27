/**
 * Точка входа Yandex Cloud Functions (обработчик `yandex.handler`).
 *
 * Одна функция в Yandex Cloud обслуживает все вызовы приложения и ночные
 * задачи. Логика — те же функции, что и для Firebase (index.ts): здесь только
 * перевод запросов Yandex в их формат.
 *
 * 1. HTTP-вызов из приложения — по протоколу callable-функций Firebase,
 *    поэтому приложение вызывает их тем же плагином cloud_functions
 *    (`httpsCallableFromUrl`), через Yandex API Gateway:
 *      POST https://<id шлюза>.apigw.yandexcloud.net/bookTraining
 *      Authorization: Bearer <ID-токен Firebase Auth>
 *      { "data": { … } }
 *    Шлюз нужен потому, что при прямом вызове функции Yandex сам проверяет
 *    заголовок Authorization как свой IAM-токен и отвечает 403.
 *    Ответ: { "result": … } или { "error": { status, message, details } }.
 * 2. Таймер Yandex Cloud с полезной нагрузкой (payload) — имя ночной задачи:
 *    expireSubscriptionsDaily или assignMonthlyFlowers.
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
  createTraining: api.createTraining,
  updateTraining: api.updateTraining,
  cancelTraining: api.cancelTraining,
  removeClientFromTraining: api.removeClientFromTraining,
  renewSubscription: api.renewSubscription,
  approveTrainerRequest: api.approveTrainerRequest,
  rejectTrainerRequest: api.rejectTrainerRequest,
  runSubscriptionExpiry: api.runSubscriptionExpiry,
};

/** Ночные задачи для таймеров. */
export const jobs: Record<string, Job> = {
  expireSubscriptionsDaily: api.expireSubscriptionsDaily,
  assignMonthlyFlowers: api.assignMonthlyFlowers,
};

/** HTTP-запрос в формате Yandex Cloud Functions. */
export interface YandexHttpEvent {
  httpMethod?: string;
  /** Через API Gateway: параметры пути (`/{fn}`). */
  pathParams?: Record<string, string | undefined>;
  headers?: Record<string, string | undefined>;
  queryStringParameters?: Record<string, string | undefined>;
  body?: string;
  isBase64Encoded?: boolean;
}

/** Срабатывание таймера Yandex Cloud. */
interface YandexTimerEvent {
  messages: Array<{ details?: { payload?: string; trigger_id?: string } }>;
}

export interface YandexHttpResponse {
  statusCode: number;
  headers: Record<string, string>;
  body: string;
}

export async function handler(
  event: YandexHttpEvent | YandexTimerEvent,
): Promise<YandexHttpResponse | { ran: string[] }> {
  if ('messages' in event && Array.isArray(event.messages)) {
    return runTimers(event);
  }
  return handleCall(event as YandexHttpEvent);
}

async function runTimers(event: YandexTimerEvent): Promise<{ ran: string[] }> {
  const ran: string[] = [];
  for (const message of event.messages) {
    const name = message.details?.payload?.trim() ?? '';
    const job = jobs[name];
    if (!job) {
      logger.error('Таймер: неизвестная задача', { payload: name, trigger: message.details?.trigger_id });
      continue;
    }
    // Ошибка пробрасывается: Yandex отметит запуск неудачным и повторит.
    await job.run({} as never);
    ran.push(name);
  }
  return { ran };
}

const json = (statusCode: number, body: unknown): YandexHttpResponse => ({
  statusCode,
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
  body: JSON.stringify(body),
});

const failure = (error: HttpsError) =>
  json(error.httpErrorCode.status, { error: error.toJSON() });

function header(event: YandexHttpEvent, name: string): string | undefined {
  const key = Object.keys(event.headers ?? {}).find((k) => k.toLowerCase() === name);
  return key ? event.headers?.[key] : undefined;
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
function corsHeaders(event: YandexHttpEvent): Record<string, string> {
  const origin = header(event, 'origin');
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

export async function handleCall(event: YandexHttpEvent): Promise<YandexHttpResponse> {
  const cors = corsHeaders(event);
  if ((event.httpMethod ?? '').toUpperCase() === 'OPTIONS') {
    return { statusCode: 204, headers: cors, body: '' };
  }
  const response = await callFunction(event);
  return { ...response, headers: { ...response.headers, ...cors } };
}

async function callFunction(event: YandexHttpEvent): Promise<YandexHttpResponse> {
  const name = event.pathParams?.fn ?? event.queryStringParameters?.fn ?? '';
  const fn = callables[name];
  if (!fn) {
    return failure(new HttpsError('not-found', `Функция «${name}» не найдена.`));
  }
  if ((event.httpMethod ?? 'POST').toUpperCase() !== 'POST') {
    return failure(new HttpsError('invalid-argument', 'Нужен POST-запрос.'));
  }

  let data: unknown;
  try {
    const raw = event.isBase64Encoded
      ? Buffer.from(event.body ?? '', 'base64').toString('utf8')
      : (event.body ?? '');
    const parsed = raw ? (JSON.parse(raw) as { data?: unknown }) : {};
    data = decode(parsed?.data ?? null);
  } catch {
    return failure(new HttpsError('invalid-argument', 'Некорректный запрос.'));
  }

  // Вход: ID-токен Firebase Auth. Нет токена — функция сама ответит
  // «нужно войти»; неверный или просроченный — отказ сразу.
  let auth: CallableRequest<unknown>['auth'];
  const bearer = header(event, 'authorization')?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (bearer) {
    try {
      const token = await getAuth().verifyIdToken(bearer);
      auth = { uid: token.uid, token, rawToken: bearer };
    } catch {
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
