import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/auth/auth_repository.dart';
import 'package:jumping_fitness/models/trainer_request.dart';
import 'package:jumping_fitness/models/user_profile.dart';
import 'package:jumping_fitness/routing/app_router.dart';
import 'package:jumping_fitness/screens/admin/trainer_requests_entry.dart';
import 'package:jumping_fitness/screens/client/client_home_screen.dart';
import 'package:jumping_fitness/screens/trainer/trainer_home_screen.dart';
import 'package:jumping_fitness/services/cloud_functions.dart';
import 'package:jumping_fitness/services/theme_mode_storage.dart';

import 'support/fake_studio.dart';
import 'support/fakes.dart';
import 'support/test_app.dart';

/// Пользователь с подтверждённой почтой для тестов экранов после входа
/// (идентификатор в подделке может быть любым).
const phone = '+79991234567';
final uid = FakeAuthRepository.uidFor(phone);

const email = 'anna@mail.ru';
const password = 'секрет-123';

Finder field(String label) => find.widgetWithText(TextField, label);

/// Нажатие с прокруткой к виджету: форма регистрации выше тестового экрана.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> fillSignUp(
  WidgetTester tester, {
  String mail = email,
  String pass = password,
  String? repeat,
}) async {
  await tester.enterText(field('Почта'), mail);
  await tester.enterText(field('Пароль'), pass);
  await tester.enterText(field('Пароль ещё раз'), repeat ?? pass);
  await tapVisible(
    tester,
    find.widgetWithText(FilledButton, 'Зарегистрироваться'),
  );
  await tester.pumpAndSettle();
}

/// ФИО и телефон на экране «Знакомство».
Future<void> fillRegistration(
  WidgetTester tester, {
  required String name,
  String tel = '8 (999) 123-45-67',
}) async {
  await tester.enterText(field('ФИО'), name);
  await tester.enterText(field('Телефон'), tel);
}

Finder dialogButton(String text) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, text),
);

Future<void> openTrainerRequests(WidgetTester tester) async {
  await tester.tap(find.byType(TrainerRequestsEntry));
  await tester.pumpAndSettle();
}

void main() {
  group('регистрация по почте', () {
    testWidgets(
      'почта и пароль → подтверждение почты → ФИО и телефон → клиент → выход',
      (tester) async {
        final auth = FakeAuthRepository();
        final backend = FakeBackend();
        await tester.pumpWidget(buildTestApp(auth: auth, backend: backend));
        await tester.pumpAndSettle();

        expect(find.text('Вход'), findsOneWidget);
        expect(find.byType(BackButton), findsNothing);
        await tapVisible(
          tester,
          find.text('Впервые здесь? Зарегистрироваться'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Регистрация'), findsOneWidget);

        // Ошибки ввода не уходят на сервер.
        await fillSignUp(tester, mail: 'anna@mail');
        expect(find.textContaining('Введите почту полностью'), findsOneWidget);
        await fillSignUp(tester, pass: 'short');
        expect(find.text('Пароль — не короче 8 символов.'), findsOneWidget);
        await fillSignUp(tester, repeat: 'другой-пароль');
        expect(find.text('Пароли не совпадают.'), findsOneWidget);
        expect(auth.signUpCalls, 0);

        // Почта приводится к нижнему регистру.
        await fillSignUp(tester, mail: '  Anna@Mail.RU ');
        expect(auth.accounts, {email: password});
        expect(auth.verificationEmails, 1);
        expect(find.text('Подтвердите почту'), findsOneWidget);
        expect(
          find.textContaining('Отправили письмо на $email'),
          findsOneWidget,
        );

        // Ссылка ещё не открыта — остаёмся и объясняем.
        await tapVisible(tester, find.text('Я подтвердил(а) почту'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Почта ещё не подтверждена'),
          findsOneWidget,
        );

        auth.confirmEmail(email);
        await tapVisible(tester, find.text('Я подтвердил(а) почту'));
        await tester.pumpAndSettle();
        expect(find.text('Знакомство'), findsOneWidget);
        expect(
          find.textContaining('Почта $email подтверждена'),
          findsOneWidget,
        );

        await tapVisible(tester, find.text('Готово'));
        expect(find.text('Введите ФИО.'), findsOneWidget);
        expect(find.textContaining('Введите номер полностью'), findsOneWidget);
        expect(backend.profiles, isEmpty);

        await fillRegistration(tester, name: '  Смирнова Анна ');
        await tapVisible(tester, find.text('Готово'));
        await tester.pumpAndSettle();

        expect(find.byType(ClientHomeScreen), findsOneWidget);
        final created = backend.profiles[FakeAuthRepository.uidFor(email)]!;
        expect(created.fullName, 'Смирнова Анна');
        expect(created.phone, '+79991234567');
        expect(created.role, UserRole.client);
        expect(backend.requests, isEmpty);

        await tester.tap(find.byTooltip('Выйти'));
        await tester.pumpAndSettle();
        await tester.tap(dialogButton('Выйти'));
        await tester.pumpAndSettle();
        expect(find.text('Вход'), findsOneWidget);
        expect(auth.current, isNull);
      },
    );

    testWidgets('«Хочу стать тренером»: заявка pending, но доступ клиента', (
      tester,
    ) async {
      final auth = FakeAuthRepository()..signInAs(phone);
      final backend = FakeBackend();
      final studio = FakeStudio(uid: uid);
      await tester.pumpWidget(
        buildTestApp(auth: auth, backend: backend, studio: studio),
      );
      await tester.pumpAndSettle();

      expect(find.text('Знакомство'), findsOneWidget);
      await fillRegistration(
        tester,
        name: 'Петрова Ольга',
        tel: '+7 916 111-22-33',
      );
      await tapVisible(tester, find.text('Хочу стать тренером'));
      await tapVisible(tester, find.text('Готово'));
      await tester.pumpAndSettle();

      expect(backend.profiles[uid]!.role, UserRole.client);
      expect(backend.requests[uid]!.status, TrainerRequestStatus.pending);
      expect(backend.requests[uid]!.phone, '+79161112233');
      // Администраторы узнают о заявке сразу.
      expect(studio.notifyTrainerRequestCalls, 1);
      expect(find.byType(ClientHomeScreen), findsOneWidget);
      expect(
        find.textContaining('Заявка на роль тренера отправлена'),
        findsOneWidget,
      );
      // Клиент не видит раздел администратора.
      expect(find.byType(TrainerRequestsEntry), findsNothing);
    });

    testWidgets('письмо ещё раз — через 60 секунд', (tester) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(buildTestApp(auth: auth, backend: FakeBackend()));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Впервые здесь? Зарегистрироваться'));
      await tester.pumpAndSettle();
      await fillSignUp(tester);

      Finder resend() => find.ancestor(
        of: find.textContaining(RegExp('^Отправить письмо ещё раз')),
        matching: find.byType(TextButton),
      );
      bool resendEnabled() =>
          tester.widget<TextButton>(resend()).onPressed != null;

      expect(find.textContaining('через 1:00'), findsOneWidget);
      expect(resendEnabled(), isFalse);
      await tester.pump(const Duration(seconds: 60));
      expect(resendEnabled(), isTrue);

      await tester.tap(resend());
      await tester.pump();
      expect(auth.verificationEmails, 2);
      expect(find.text('Письмо отправлено ещё раз.'), findsOneWidget);
      expect(resendEnabled(), isFalse);

      // «Другая почта» — выход к экрану входа.
      await tapVisible(tester, find.text('Другая почта'));
      await tester.pumpAndSettle();
      expect(find.text('Вход'), findsOneWidget);
    });

    testWidgets('выход на экране регистрации возвращает ко входу', (
      tester,
    ) async {
      final auth = FakeAuthRepository()..signInAs(phone);
      await tester.pumpWidget(buildTestApp(auth: auth, backend: FakeBackend()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Выйти'));
      await tester.pumpAndSettle();
      expect(find.text('Вход'), findsOneWidget);
    });
  });

  group('вход и пароль', () {
    testWidgets('неверный пароль — ошибка; верный — сразу главный экран', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..accounts[email] = password
        ..confirmEmail(email);
      final backend = FakeBackend()
        ..putProfile(profile(uid: FakeAuthRepository.uidFor(email)));
      await tester.pumpWidget(buildTestApp(auth: auth, backend: backend));
      await tester.pumpAndSettle();

      await tester.enterText(field('Почта'), email);
      await tester.enterText(field('Пароль'), 'не-тот');
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();
      expect(
        find.text(AuthFailureKind.wrongCredentials.message),
        findsOneWidget,
      );

      await tester.enterText(field('Пароль'), password);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();
      expect(find.byType(ClientHomeScreen), findsOneWidget);
    });

    testWidgets('пустой пароль на сервер не уходит', (tester) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(buildTestApp(auth: auth, backend: FakeBackend()));
      await tester.pumpAndSettle();

      await tester.enterText(field('Почта'), email);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();
      expect(find.text('Введите пароль.'), findsOneWidget);
      expect(auth.signInCalls, 0);
    });

    testWidgets('«Забыли пароль?» — письмо со ссылкой', (tester) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(buildTestApp(auth: auth, backend: FakeBackend()));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Забыли пароль?'));
      await tester.pumpAndSettle();
      expect(find.text('Новый пароль'), findsOneWidget);
      expect(field('Пароль'), findsNothing);

      await tester.enterText(field('Почта'), email);
      await tapVisible(tester, find.text('Отправить ссылку'));
      await tester.pumpAndSettle();
      expect(auth.resetEmails, [email]);
      // Сразу обратно ко входу — с подсказкой про письмо.
      expect(find.text('Вход'), findsOneWidget);
      expect(find.textContaining('ссылкой для нового пароля'), findsOneWidget);
    });

    testWidgets('сервер отклонил — сообщение, остаёмся на входе', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..nextFailure = const AuthFailure(AuthFailureKind.tooManyRequests);
      await tester.pumpWidget(buildTestApp(auth: auth, backend: FakeBackend()));
      await tester.pumpAndSettle();

      await tester.enterText(field('Почта'), email);
      await tester.enterText(field('Пароль'), password);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();
      expect(
        find.text(AuthFailureKind.tooManyRequests.message),
        findsOneWidget,
      );
      expect(find.text('Вход'), findsOneWidget);
    });

    testWidgets('сервер не подключён — предупреждение и понятная ошибка', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('ещё не подключено к серверу'),
        findsOneWidget,
      );
      await tester.enterText(field('Почта'), email);
      await tester.enterText(field('Пароль'), password);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();
      expect(find.text(AuthFailureKind.notConfigured.message), findsOneWidget);
    });
  });

  group('роли и навигация', () {
    testWidgets('тренер попадает на экран тренера, без раздела заявок', (
      tester,
    ) async {
      final auth = FakeAuthRepository()..signInAs(phone);
      final backend = FakeBackend()
        ..putProfile(profile(uid: uid, role: UserRole.trainer));
      await tester.pumpWidget(buildTestApp(auth: auth, backend: backend));
      await tester.pumpAndSettle();

      expect(find.byType(TrainerHomeScreen), findsOneWidget);
      expect(find.byType(TrainerRequestsEntry), findsNothing);
    });

    testWidgets('одобрение заявки на лету переводит клиента к тренеру', (
      tester,
    ) async {
      final auth = FakeAuthRepository()..signInAs(phone);
      final backend = FakeBackend()
        ..putProfile(profile(uid: uid))
        ..putRequest(request(uid: uid));
      await tester.pumpWidget(buildTestApp(auth: auth, backend: backend));
      await tester.pumpAndSettle();
      expect(find.byType(ClientHomeScreen), findsOneWidget);

      // Клиент в этот момент в настройках — после смены роли окно закроется.
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();

      await backend.approve(uid);
      await tester.pumpAndSettle();
      expect(find.byType(TrainerHomeScreen), findsOneWidget);
      expect(find.text('Тема оформления'), findsNothing);
    });

    testWidgets('отклонённая заявка — клиент видит, что её отклонили', (
      tester,
    ) async {
      final auth = FakeAuthRepository()..signInAs(phone);
      final backend = FakeBackend()
        ..putProfile(profile(uid: uid))
        ..putRequest(request(uid: uid));
      await tester.pumpWidget(buildTestApp(auth: auth, backend: backend));
      await tester.pumpAndSettle();

      await backend.reject(uid);
      await tester.pumpAndSettle();
      expect(find.byType(ClientHomeScreen), findsOneWidget);
      expect(find.textContaining('отклонили'), findsOneWidget);
    });

    testWidgets('экран заявок по маршруту без флага админа — «Нет доступа»', (
      tester,
    ) async {
      final auth = FakeAuthRepository()..signInAs(phone);
      final backend = FakeBackend()
        ..putProfile(profile(uid: uid, role: UserRole.trainer))
        ..putRequest(request(uid: 'other'));
      await tester.pumpWidget(buildTestApp(auth: auth, backend: backend));
      await tester.pumpAndSettle();

      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed(AppRoutes.trainerRequests);
      await tester.pumpAndSettle();
      expect(find.text('Нет доступа'), findsOneWidget);
      expect(find.text('Ольга Петрова'), findsNothing);
    });
  });

  group('заявки в тренеры (администратор)', () {
    late FakeAuthRepository adminAuth;

    Future<FakeBackend> openAsAdmin(WidgetTester tester) async {
      final auth = adminAuth = FakeAuthRepository()..signInAs(phone);
      final backend = FakeBackend()
        // Админ-разработчик: роль client, но флаг isAdmin (ТЗ 2).
        ..putProfile(profile(uid: uid, fullName: 'Разработчик', isAdmin: true))
        ..putProfile(profile(uid: 'olga', fullName: 'Ольга Петрова'))
        ..putRequest(
          request(
            uid: 'olga',
            // 11:05 UTC = 14:05 по Москве.
            createdAt: DateTime.utc(2026, 9, 26, 11, 5),
          ),
        )
        ..putProfile(profile(uid: 'ira', fullName: 'Ирина Волкова'))
        ..putRequest(
          request(
            uid: 'ira',
            fullName: 'Ирина Волкова',
            phone: '+79990000003',
            createdAt: DateTime.utc(2026, 9, 27, 9),
          ),
        );
      await tester.pumpWidget(buildTestApp(auth: auth, backend: backend));
      await tester.pumpAndSettle();

      // У админа все права тренера — его главный экран тренерский.
      expect(find.byType(TrainerHomeScreen), findsOneWidget);
      await openTrainerRequests(tester);
      return backend;
    }

    testWidgets('список: ФИО, телефон, дата подачи; старые сверху', (
      tester,
    ) async {
      await openAsAdmin(tester);

      expect(find.text('Заявки в тренеры'), findsOneWidget);
      expect(find.text('Ольга Петрова'), findsOneWidget);
      expect(find.text('+7 999 000-00-02'), findsOneWidget);
      expect(find.text('Подана 26 сентября 2026, 14:05'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Ольга Петрова')).dy,
        lessThan(tester.getTopLeft(find.text('Ирина Волкова')).dy),
      );
    });

    testWidgets('одобрить: подтверждение, вызов сервера, заявка уходит', (
      tester,
    ) async {
      final backend = await openAsAdmin(tester);

      // Передумали в окне подтверждения — ничего не происходит.
      await tester.tap(find.text('Одобрить').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(backend.approved, isEmpty);

      await tester.tap(find.text('Одобрить').first);
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('Одобрить'));
      await tester.pumpAndSettle();

      expect(backend.approved, ['olga']);
      expect(backend.profiles['olga']!.role, UserRole.trainer);
      expect(find.text('Ольга Петрова теперь тренер.'), findsOneWidget);
      expect(find.text('+7 999 000-00-02'), findsNothing);
      expect(find.text('Ирина Волкова'), findsOneWidget);
    });

    testWidgets('отклонить; пустой список — понятная надпись', (tester) async {
      final backend = await openAsAdmin(tester);

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Отклонить').first);
        await tester.pumpAndSettle();
        await tester.tap(dialogButton('Отклонить'));
        await tester.pumpAndSettle();
      }

      expect(backend.rejected, ['olga', 'ira']);
      expect(backend.profiles['olga']!.role, UserRole.client);
      expect(find.text('Новых заявок нет'), findsOneWidget);
    });

    testWidgets('ошибка сервера — сообщение, заявка остаётся', (tester) async {
      final backend = await openAsAdmin(tester);
      backend.decisionFailure = const CloudFunctionFailure(
        'Эта заявка уже рассмотрена.',
        'failed-precondition',
      );

      await tester.tap(find.text('Одобрить').first);
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('Одобрить'));
      await tester.pumpAndSettle();

      expect(find.text('Эта заявка уже рассмотрена.'), findsOneWidget);
      expect(find.text('Ольга Петрова'), findsOneWidget);
      expect(backend.approved, isEmpty);
    });

    testWidgets('выход из аккаунта закрывает экран заявок', (tester) async {
      await openAsAdmin(tester);

      await adminAuth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Вход'), findsOneWidget);
      expect(find.text('Заявки в тренеры'), findsNothing);
      expect(find.byType(BackButton), findsNothing);
    });
  });

  testWidgets('настройки: переключение темы применяется и сохраняется', (
    tester,
  ) async {
    final storage = InMemoryThemeModeStorage(ThemeMode.light);
    await tester.pumpWidget(buildTestApp(themeStorage: storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();

    expect(find.text('Светлая'), findsOneWidget);
    expect(find.text('Тёмная'), findsOneWidget);
    expect(find.text('Как в системе'), findsOneWidget);

    Brightness currentBrightness() =>
        Theme.of(tester.element(find.text('Тёмная'))).brightness;

    expect(currentBrightness(), Brightness.light);

    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();
    expect(currentBrightness(), Brightness.dark);
    expect(storage.value, ThemeMode.dark);

    // pageBack() ищет подсказку «Back», а в русской локализации она «Назад».
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Вход'), findsOneWidget);
  });

  test('неизвестный маршрут ведёт на запасной экран, а не падает', () {
    final route = AppRouter.onGenerateRoute(const RouteSettings(name: '/nope'));
    expect(route.settings.name, '/nope');
  });

  test('стартовый стек — только корень', () {
    final routes = AppRouter.onGenerateInitialRoutes(AppRouter.initialRoute);
    expect(routes, hasLength(1));
    expect(routes.single.settings.name, AppRoutes.home);
  });
}
