# Перенос серверных функций с Yandex Cloud на Netlify

Что переезжает: только серверные функции (бронирование, отмена, заморозка,
заявки в тренеры, журнал ошибок, ночные задачи). Firebase (вход, база,
push, сайт `jumpingfitness.web.app`) остаётся как есть.

## Как это устроено в коде

```
functions/src/http_api.ts      общее HTTP API: протокол, вход, CORS, список функций
functions/src/yandex.ts        адаптер Yandex (как было)
functions/src/netlify.ts       адаптер Netlify
functions/netlify/functions/   функции, которые видит Netlify:
  api.mjs                        POST https://<сайт>.netlify.app/api/<имя функции>
  expire-daily.mjs               сгорание абонементов, 21:05 UTC (00:05 МСК)
  flowers-daily.mjs              цветы месяца, 21:10 UTC (00:10 МСК)
netlify.toml                   настройки сборки (корень репозитория)
```

Бизнес-логика общая, поэтому обе площадки могут работать **одновременно**.
Ночные задачи идемпотентны, и двойной запуск ничего не испортит.

Проверка на компьютере:
- `npm run test:netlify` в `firebase/tests` прогоняет все тесты функций через адаптер Netlify;
- `npm run dev:api:netlify` в `functions` поднимает локальный сервер на `http://127.0.0.1:5003/api`.

## Тариф и ограничения

Бесплатный тариф Netlify (Free) даёт 300 кредитов в месяц. Из них расходуется:

| Что | Цена | Наш расход в месяц |
|---|---|---|
| Выкладка в прод | 15 кредитов | **главная статья:** 20 выкладок съедают весь лимит |
| Работа функций | 5 кредитов за ГБ·час | ~3–5 кредитов |
| Запросы | 3 кредита за 10 000 | ~1–2 кредита |

- **Выкладывайте редко.** `netlify.toml` пересобирает сервер только при
  изменениях в `functions/` или в самом `netlify.toml`. Правки приложения,
  документов и веба кредиты не тратят.
- **Что будет при перерасходе:** на бесплатном тарифе сайт, исчерпавший кредиты,
  приостанавливается до следующего месяца. Карты нет, поэтому счёт не придёт.
  Остаток виден в **Billing → Usage**.
- **Доступ из России:** Netlify — зарубежный сервис, сейчас он работает, но
  гарантий нет. Поэтому Yandex выключаем последним, когда всё проверено.

## Шаги (делаете вы)

### 1. Аккаунт и сайт

1. Зайдите на https://app.netlify.com и войдите **через GitHub** (аккаунт FalkM49).
2. Выберите **Add new project → Import an existing project → GitHub**.
   Разрешите доступ к репозиторию `jumping-fitness`.
3. На странице настроек ничего не меняйте: всё берётся из `netlify.toml`
   (Base directory `functions`, Build command `npm run build`).
   **Deploy пока не нажимайте**, если есть кнопка «Add environment variables» —
   сначала шаг 2. Если сборка уже запустилась, ничего страшного: после шага 2
   нажмите **Deploys → Trigger deploy**.

### 2. Ключ Firebase (секрет)

Скопируйте ключ в буфер одной строкой, не показывая его на экране:

```powershell
Get-Content E:\keys\jf-admin.json -Raw | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 5 | Set-Clipboard
```

Дальше: **Project configuration → Environment variables → Add a variable**:
- Key: `FIREBASE_SERVICE_ACCOUNT`;
- Value: вставить (Ctrl+V);
- отметить **Contains secret values**;
- Scopes: **Functions**;
- сохранить.

После этого очистите буфер, скопировав любой другой текст.

### 3. Имя сайта и регион

- **Project configuration → General → Change project name**, например
  `jumpingfitness-api`. Адрес API станет `https://jumpingfitness-api.netlify.app/api`.
- **Project configuration → Build & deploy → Functions → Functions region**:
  если выбор доступен, поставьте **EU (Frankfurt) eu-central-1**. Firestore
  тоже во Франкфурте, и функции будут работать быстрее.
- **Deploys → Trigger deploy → Deploy project.**

### 4. Проверка сервера

В разделе **Logs → Functions** должны появиться `api`, `expire-daily` и
`flowers-daily` (последние две с пометкой Scheduled). Затем в PowerShell:

```powershell
Invoke-WebRequest -Method Post -Uri https://jumpingfitness-api.netlify.app/api/ensureMonthlyFlower -ContentType 'application/json' -Body '{"data":{}}'
```

Ожидается ошибка **401** с `UNAUTHENTICATED`: это нормально, значит сервер
жив и требует вход. Ошибка 500 или пустой ответ означают, что ключ из шага 2
не подхватился (смотрите журнал функции `api`).

### 5. Проверка веб-версии на предпросмотре

Напишите Claude адрес сайта. Он соберёт веб с новым сервером и выложит на
канал предпросмотра (сами команды):

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_web.ps1 -ApiUrl https://jumpingfitness-api.netlify.app/api
firebase hosting:channel:deploy netlify --expires 7d
```

На предпросмотре проверьте: вход, запись на тренировку, отмену, заморозку
(клиент); создание тренировки (тренер); push-уведомление.

### 6. Переключение

Claude меняет адрес сервера по умолчанию в `lib/services/cloud_functions.dart`, после этого:

1. Выкладывается веб: у iPhone он обновится сам.
2. Собирается новый APK и выкладывается по ссылке `/android`. **Старые APK
   продолжают ходить в Yandex**, поэтому клиентам на Android нужно
   переустановить приложение по ссылке.

### 7. Выключение Yandex

Пока у всех не стоит новый APK, Yandex оставляем. Он почти бесплатный,
кроме Lockbox. Потом в консоли Yandex Cloud:

1. **Cloud Functions → Триггеры:** удалить `jf-expire-daily` и `jf-flowers-daily`.
2. **API Gateway:** удалить `jumping-fitness-gateway`.
3. **Cloud Functions:** удалить `jumping-fitness-api`.
4. **Lockbox:** удалить `firebase-service-account`. Это и была главная статья расходов.
5. **Object Storage:** бакет `jumpingfitness-download` хранит APK для ссылки
   `/android`. Его либо оставить (копейки), либо перенести APK, например в
   GitHub Releases, и поменять перенаправление в `firebase.json`.

Старый ключ сервисного аккаунта Firebase, который лежал в Lockbox, можно
отозвать в консоли Firebase (**Project settings → Service accounts**), если
для Netlify создавался новый.

## Откат

Если с Netlify что-то не так, а Yandex ещё работает, пересоберите веб с
адресом Yandex и выложите `firebase deploy --only hosting`:
- до шага 6 — без `-ApiUrl`;
- после шага 6 — с `-ApiUrl https://d5dg4jlie0pflgjhlb0c.fovt0b64.apigw.yandexcloud.net`.
