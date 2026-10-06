# Jumping Fitness

Мобильное приложение (iOS + Android) для записи на групповые тренировки и учёта абонементов.
Flutter + Firebase. Полная спецификация лежит в базе знаний проекта: «Промт_для_приложения_ИТОГ.md».

Текущее состояние: **этап 8** — проект подключён к Firebase (Spark) и Yandex Cloud. Готовы:
- каркас с темой, схема данных Firestore, Security Rules, модели;
- вход по почте и паролю с подтверждением почты, регистрация (ФИО, телефон, роль), экран «Заявки в тренеры», выбор экрана по роли;
- все Cloud Functions бизнес-логики: запись, отмена, тренировки, заморозка, продление,
  сгорание тренировок, цветок месяца;
- экран клиента: календарь с записью и отменой, профиль с цветком месяца, абонемент
  с заморозкой и баннерами;
- экран тренера: тот же календарь с правкой, созданием и отменой тренировок, списком
  записавшихся и «мусоркой», профиль с плашкой «Тренер», клиенты с поиском, сортировкой
  и продлением абонемента;
- уведомления: push через FCM и история в приложении по всем событиям ТЗ, баннер при
  открытом приложении, переход по тапу к нужной тренировке; тёмная тема с переключателем.

**Развёртывание и эксплуатация:** [ИНСТРУКЦИЯ_ПО_ЭКСПЛУАТАЦИИ.md](../ИНСТРУКЦИЯ_ПО_ЭКСПЛУАТАЦИИ.md) —
создание проекта Firebase, деплой, сборка для Android и iPhone, администрирование, расходы.
Чек-лист тестирования: [docs/08_test_checklist.md](08_test_checklist.md).

- Схема данных и правила доступа: [docs/02_firestore_schema.md](02_firestore_schema.md).
- Cloud Functions (аргументы, проверки, причины отказа):
  [docs/04_cloud_functions.md](04_cloud_functions.md).

---

## Первый запуск

Нужен Flutter **3.44 или новее** (рекомендуется текущий stable 3.47.x).

```bash
# 1. Сгенерировать платформенные папки android/ и ios/.
#    Существующие файлы (lib/, test/, pubspec.yaml) команда НЕ перезаписывает.
#    --org задаёт идентификатор пакета (ru.jumpingfitness.jumping_fitness).
#    Он понадобится на этапе 8 при регистрации приложения в Firebase,
#    поэтому выберите его сейчас и потом не меняйте.
flutter create . --org ru.jumpingfitness --project-name jumping_fitness --platforms=android,ios

# 2. Установить зависимости
flutter pub get

# 3. Проверить код и прогнать тесты
flutter analyze
flutter test

# 4. Запустить на эмуляторе или телефоне
flutter run
```

До этапа 8 настоящий проект Firebase не подключён. Приложение это распознаёт и запускается
без него: на экране входа будет предупреждение, а войти не получится. Чтобы проверить
вход и роли уже сейчас, используйте локальные эмуляторы (следующий раздел).

---

## Проверка входа и ролей на локальных эмуляторах Firebase

Эмуляторы Auth, Firestore и Cloud Functions работают на компьютере, с проектом
`demo-jumping-fitness`: настоящий Firebase не нужен, письма не отправляются.
Нужны Node.js 20+ и Java 11+.

```bash
# 1. Один раз: зависимости функций
cd functions
npm install

# 2. Запустить эмуляторы (окно не закрывать). Данные сохраняются
#    между запусками в firebase/dev/emulator-data.
npm run emulators

# 3. В другом окне, из корня проекта: приложение в режиме эмуляторов
flutter run --dart-define=USE_FIREBASE_EMULATORS=true
```

- **Справочники**: `npm run dev:seed` — один раз после первого запуска эмуляторов
  загружает 14 цветков и settings/defaults.
- **Клиент для проверки экранов клиента**: `npm run dev:client -- irina@mail.ru "Ирина Волкова"` —
  клиент с действующим абонементом (осталось 8 из 11). Войдите в приложение с этим номером.
- **Письма** (подтверждение почты, сброс пароля): `npm run dev:links` в папке `functions` — открыть ссылку в браузере на этом компьютере.
- **Сделать себя администратором**: зарегистрируйтесь в приложении, затем
  `npm run dev:make-admin -- anna@mail.ru`. Экран сменится сам, в шапке появится
  значок «Заявки в тренеры».
- **Заявка в тренеры для проверки**: `npm run dev:trainer-request -- olga@mail.ru "Ольга Петрова"` —
  создаёт пользователя (пароль `password123`) и заявку тем же путём, что приложение (вход + запись через правила).
- **Телефон вместо Android-эмулятора**: добавьте
  `--dart-define=FIREBASE_EMULATOR_HOST=<IP компьютера в Wi-Fi>` и запустите эмуляторы
  с `host: 0.0.0.0` в `firebase.json` (по умолчанию они слушают только этот компьютер).

Шрифты Unbounded и Manrope при первом запуске скачиваются из Google Fonts
(нужен интернет), затем берутся из кэша. Перед публикацией их вшивают в приложение
как ассеты, чтобы не было запросов в сеть.

---

## Структура проекта

```
lib/
├── main.dart                  Точка входа: чтение выбора темы, инициализация Firebase, запуск
├── app.dart                   MaterialApp: темы, режим темы, русская локаль, роутинг
├── firebase_options.dart      Подключение к проекту jumpingfitness (создан `flutterfire configure`)
│
├── theme/                     Дизайн-система (раздел 11 ТЗ)
│   ├── app_colors.dart        Все цветовые токены: светлые, тёмные, тона месяцев, шкала остатка
│   ├── app_palette.dart       ThemeExtension с цветами вне ColorScheme + monthToneFor(), remainingColor()
│   ├── app_typography.dart    Unbounded/Manrope, TextTheme, именованные стили (appTitle, dayPart, …)
│   ├── app_radii.dart         Радиусы: dense (4px) и petal (24/4/4/4)
│   ├── app_theme.dart         Сборка ThemeData для светлой и тёмной темы
│   ├── theme_mode_controller.dart  Состояние «Светлая / Тёмная / Как в системе»
│   └── theme_context.dart     Короткий доступ: context.palette, context.textStyles
│
├── routing/
│   └── app_router.dart        Имена маршрутов и onGenerateRoute
│
├── auth/                      Вход и роли (раздел 2 ТЗ)
│   ├── auth_repository.dart   Интерфейс входа по почте, причины ошибок с текстами
│   ├── firebase_auth_repository.dart  Firebase Phone Auth + заглушка «сервер не подключён»
│   ├── login_controller.dart  Вход, регистрация, сброс пароля; email_address.dart — проверка почты и пароля
│   ├── session.dart           Кто вошёл и какой экран положен (клиент / тренер / админ)
│   ├── phone_number.dart      Телефон для связи в любом привычном виде → +7XXXXXXXXXX
│   └── full_name.dart         Проверка ФИО — та же, что в правилах Firestore
│
├── services/
│   ├── firebase_bootstrap.dart    Инициализация Firebase или локальных эмуляторов
│   ├── backend_providers.dart     Репозитории: настоящие или заглушки, по состоянию Firebase
│   ├── user_repository.dart       Профиль и своя заявка; регистрация одним batch
│   ├── trainer_requests_repository.dart  Заявки для админа; решение — через Cloud Function
│   ├── cloud_functions.dart       Регион функций, ошибки функций → текст и причина отказа
│   ├── studio_repository.dart     Чтение: календарь, мои записи, абонемент, цветок, настройки
│   ├── studio_functions.dart      Действия клиента через Cloud Functions: запись, отмена, заморозка
│   └── theme_mode_storage.dart    Сохранение выбора темы на устройстве (shared_preferences)
│
├── client/                    Логика календаря и экрана клиента без интерфейса
│   ├── calendar_cells.dart    Что в ячейке для клиента и для тренера (режим календаря)
│   ├── booking_rules.dart     Причина для значка (i): почему нельзя записаться или отменить
│   └── client_providers.dart  Живые данные: отрезок календаря, абонемент, цветок
│
├── notifications/             Уведомления (этап 7)
│   ├── push_service.dart      FCM: разрешение, токен устройства, входящие и открытые push
│   ├── push_coordinator.dart  Баннер при открытом приложении, переход по тапу на push
│   ├── notifications_repository.dart  История users/{uid}/notifications
│   ├── notification_providers.dart    Счётчик непрочитанных, переход, выход с отвязкой
│   └── deep_link.dart         Куда ведёт уведомление: ячейка тренировки, заявки, абонемент
│
├── trainer/                   Логика экрана тренера без интерфейса
│   ├── client_list.dart       Клиенты: остаток, поиск по ФИО, сортировка, русский алфавит
│   └── trainer_providers.dart Клиенты, текущие абонементы, записавшиеся на тренировку
│
├── utils/
│   └── ru_format.dart         Даты, дни недели, месяцы, склонения по-русски (время студии)
│
├── models/                    Модели данных Firestore (схема — docs/02_firestore_schema.md)
│   ├── models.dart            Экспорт всех моделей одной строкой
│   ├── user_profile.dart      users/{uid}: роль, ФИО, телефон, цветок месяца
│   ├── trainer_request.dart   trainer_requests/{uid}: заявка в тренеры
│   ├── app_settings.dart      settings/defaults: значения по умолчанию из ТЗ
│   ├── calendar_slot.dart     calendar_slots/{день_слот}: что стоит в ячейке
│   ├── training.dart          trainings/{id}: тренировка (+ виртуальная по умолчанию)
│   ├── booking.dart           trainings/{id}/bookings/{uid}: запись клиента
│   ├── subscription.dart      subscriptions/{id}: абонемент, заморозка, остаток дней
│   ├── flower.dart            flowers/{id}: справочник цветков
│   ├── calendar_day.dart      День студии (YYYY-MM-DD по Москве)
│   ├── day_slot.dart          Утро / Вечер, граница 14:00, время HH:mm, ключ ячейки
│   ├── firestore_paths.dart   Имена коллекций
│   └── firestore_parsing.dart Строгое чтение полей с понятными ошибками
│
├── screens/
│   ├── auth/                  Корень по роли (auth_gate), вход по почте, «Подтвердите почту», регистрация
│   ├── admin/                 «Заявки в тренеры» и вход в них со счётчиком — только админу
│   ├── shared/                Общий календарь (studio_calendar), профиль, шапка, настройки, 404
│   ├── client/                Экран клиента: окно тренировки, абонемент и заморозка
│   └── trainer/               Экран тренера: окно ячейки, клиенты, карточка и продление
│
└── widgets/                   Переиспользуемые виджеты
    ├── app_title.dart         Название «Jumping Fitness» для шапки
    ├── petal_card.dart        Карточка-«лепесток» для смысловых блоков
    ├── section_title.dart     Подпись раздела главного экрана
    ├── trainer_badge.dart     Плашка «Тренер» (скруглённая — согласованное исключение)
    ├── number_stepper.dart    Число с «−»/«+»: места, длительность, тренировки, дни
    ├── flower_art.dart        Иллюстрации 14 цветков месяца (рисуются кодом, цвета палитры)
    ├── ice_cube_icon.dart     Линейный значок кубика льда для заморозки
    ├── info_notice.dart       Плашка-подсказка и баннеры (обычный, внимание, тревога)
    ├── theme_mode_selector.dart   Переключатель темы
    └── screen_placeholder.dart    Временное содержимое заглушек

functions/                     Cloud Functions (TypeScript): вся строгая логика (раздел 8 ТЗ)
├── src/index.ts               Список всех функций
├── src/bookings.ts            bookTraining, cancelBooking, removeClientFromTraining
├── src/trainings.ts           createTraining, updateTraining, cancelTraining
├── src/subscriptions.ts       freezeSubscription, renewSubscription
├── src/expiry.ts              Ежедневное сгорание тренировок + ручной запуск для админа
├── src/trainer_requests.ts    approveTrainerRequest / rejectTrainerRequest
├── src/calendar.ts            Ячейки и тренировки по расписанию (создание при первой записи)
├── src/refunds.ts             Куда вернуть тренировку при отмене
├── src/auth.ts, args.ts       Проверка роли вызывающего, разбор аргументов
├── src/time.ts, settings.ts   Время студии (Москва), значения по умолчанию
├── src/notifications.ts       sendNotification: история в приложении + push через FCM
└── scripts/                   Эмуляторы, ссылки из писем, флаг админа, тестовая заявка, seed.mjs — справочники,
                               deploy-yandex.mjs — выкладка в Yandex Cloud, yandex-local.mjs — переходник локально
                               (эмулятор или настоящий проект: npm run seed -- --project <id> --key <ключ>)

firestore.rules                Security Rules (раздел 8 ТЗ)
firestore.indexes.json         Составные индексы
firebase.json                  Конфигурация Firebase CLI (правила, индексы, функции, эмуляторы)
firebase.test.json             Эмуляторы для автотестов — на своих портах, не мешают разработке
firebase/
├── seed/flowers.json          14 цветков из раздела 12 ТЗ
├── seed/settings_defaults.json    Документ settings/defaults
└── tests/                     Тесты на эмуляторах: npm test (правила), npm run test:functions
docs/
├── 02_firestore_schema.md     Схема Firestore: коллекции, поля, доступ, индексы
├── 04_cloud_functions.md      Все функции: аргументы, проверки, причины отказа
└── 08_test_checklist.md       Чек-лист тестирования перед раздачей

test/
├── auth_test.dart                 Телефон, ФИО, ошибки входа, сессия и роли, контроллер входа
├── widget_test.dart               Вход, регистрация, смена роли на лету, экран заявок, тема
├── models_test.dart               Разбор документов, даты по Москве, сиды
├── app_theme_test.dart            Токены, радиусы, шрифты, шкала остатка, тона месяцев
├── theme_mode_controller_test.dart    Переключение и сохранение темы
└── support/                       Подделки Firebase в памяти для тестов
```

---

## Архитектурные решения

### Состояние: Riverpod (`flutter_riverpod` 3.x)

- **Потоки Firestore ложатся естественно.** Календарь, профиль, абонемент и список клиентов —
  это живые подписки на Firestore. `StreamProvider` даёт состояния «загрузка / данные / ошибка»
  без ручного кода.
- **Зависимости между данными явные.** Абонемент зависит от текущего пользователя,
  а экран — от его роли. В Riverpod это выражается через `ref.watch`, и при выходе
  из аккаунта всё пересчитывается автоматически.
- **Легко тестировать.** Любой сервис подменяется через `overrides`, как в тестах
  этого этапа, где SharedPreferences заменён хранилищем в памяти, а сетевые шрифты — локальными.
  Позже так же будут подменяться Firestore и Cloud Functions.
- **Проверки на этапе компиляции.** Провайдеры не ищутся по типу во время работы,
  как в Provider, поэтому нет ошибок вида «ProviderNotFoundException».
- **Против Bloc.** Для приложения на ~20 пользователей Bloc дал бы заметно больше шаблонного кода
  (события и состояния на каждое действие) без выигрыша. Вся строгая логика по ТЗ
  всё равно живёт на сервере, в Cloud Functions.

### Роутинг: встроенный Navigator с таблицей маршрутов

У каждой роли один главный экран (календарь → профиль → абонемент или клиенты),
а всё остальное — модальные окна поверх него. Поэтому стороннего роутера не нужно.

### Вход и роли (этап 3)

- **Один корневой экран решает, что показать** (`screens/auth/auth_gate.dart`): вход,
  регистрацию или главный экран роли. Отдельных маршрутов «клиент» и «тренер» нет,
  поэтому попасть на чужой экран по имени маршрута нельзя.
- **Роль читается из профиля в Firestore в реальном времени.** Одобрили заявку — клиент
  сразу оказывается на экране тренера; сняли флаг админа — экран заявок закрывается.
  Администратор (флаг `isAdmin`) видит экран тренера плюс раздел «Заявки в тренеры».
- **Регистрация — одна запись batch**: профиль с ролью `client` и, при выборе
  «Хочу стать тренером», заявка `pending`. Доступ клиента выдаётся сразу (ТЗ 2).
- **Решение по заявке принимает только Cloud Function**: правила запрещают приложению
  менять роль и статус заявки. Push об одобрении подключается на этапе 7 —
  место отмечено TODO в `functions/src/notifications.ts`.
- **Вход по почте** (согласованная замена SMS): без подтверждённой почты правила Firestore
  не дают ни читать, ни регистрироваться, а приложение показывает «Подтвердите почту».

### Уведомления (этап 7) — что понадобится на этапе 8

- **Android**: push заработают сами после `flutterfire configure`. Разрешение
  POST_NOTIFICATIONS уже в манифесте, приложение спрашивает его после входа.
- **iOS**: ключ APNs (.p8) в Firebase Console, в Xcode — возможности Push Notifications
  и Background Modes → Remote notifications.
- **Сервер — в Yandex Cloud** (согласованная замена Firebase Cloud Functions, тариф Blaze
  недоступен из России): переходник `functions/src/yandex.ts`, выкладка `npm run deploy:yc`,
  подробности — в конце [docs/04_cloud_functions.md](04_cloud_functions.md).
- На локальных эмуляторах push не отправляются (у эмулятора нет FCM), но история
  уведомлений пишется. Её видно в приложении под колокольчиком.

### Material

Используется встроенный `package:flutter/material.dart`. Во Flutter 3.47 Material
вынесен в отдельный пакет `material_ui`, но старый импорт полностью поддерживается,
а официальная пометка «устаревший» ожидается только в ноябрьском релизе.
Переход делается одной командой:

```bash
dart fix --apply --code=migrate_design_widgets
```

Его стоит выполнить, когда Firebase-плагины и `google_fonts` тоже перейдут на новый пакет.

---

## Веб-версия (iPhone)

Сборка — только через скрипт, он задаёт нужные флаги (docs/09, шаг 7):

```bash
powershell -ExecutionPolicy Bypass -File tool\build_web.ps1            # боевая
powershell -ExecutionPolicy Bypass -File tool\build_web.ps1 -Emulators # локальные эмуляторы + npm run dev:api
powershell -ExecutionPolicy Bypass -File tool\build_web.ps1 -Wasm      # эксперимент с WebAssembly
```

- `--no-web-resources-cdn` — движок CanvasKit с нашего хостинга, не с gstatic.com.
- `--source-maps` — `main.dart.js.map` для расшифровки стеков из журнала ошибок.
- `APP_VERSION` — версия из `pubspec.yaml`, попадает в отчёты (`lib/main.dart`).
- `web/flutter_bootstrap.js` — свой загрузчик без устаревшего service worker Flutter
  (и снимает его у тех, кто открывал сайт раньше); push-воркер — `web/firebase-messaging-sw.js`.
- Журнал ошибок веба: `lib/services/error_reporter.dart` → функция `reportClientError`
  → логи Yandex Cloud. Работает только в release-сборке для веба.
