/**
 * Точка входа Yandex Cloud Functions (обработчик `yandex.handler`).
 *
 * Одна функция в Yandex Cloud обслуживает все вызовы приложения и ночные
 * задачи. Сам протокол и список функций — в http_api.ts; здесь только
 * перевод запросов Yandex в его формат.
 *
 * 1. HTTP-вызов из приложения — через Yandex API Gateway:
 *      POST https://<id шлюза>.apigw.yandexcloud.net/bookTraining
 *    Шлюз нужен потому, что при прямом вызове функции Yandex сам проверяет
 *    заголовок Authorization как свой IAM-токен и отвечает 403.
 * 2. Таймер Yandex Cloud с полезной нагрузкой (payload) — имя ночной задачи:
 *    expireSubscriptionsDaily или assignMonthlyFlowers.
 */
import { logger } from 'firebase-functions';

import { ApiResponse, handleApiRequest, runJob } from './http_api.js';

export { callables, decode, jobs } from './http_api.js';

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

export type YandexHttpResponse = ApiResponse;

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
    // Ошибка пробрасывается: Yandex отметит запуск неудачным и повторит.
    if (await runJob(name)) {
      ran.push(name);
    } else {
      logger.error('Таймер: неизвестная задача', { payload: name, trigger: message.details?.trigger_id });
    }
  }
  return { ran };
}

export function handleCall(event: YandexHttpEvent): Promise<YandexHttpResponse> {
  return handleApiRequest({
    method: event.httpMethod ?? 'POST',
    fn: event.pathParams?.fn ?? event.queryStringParameters?.fn ?? '',
    headers: event.headers ?? {},
    body: event.isBase64Encoded
      ? Buffer.from(event.body ?? '', 'base64').toString('utf8')
      : (event.body ?? ''),
  });
}
