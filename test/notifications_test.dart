import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/models/models.dart';
import 'package:jumping_fitness/notifications/deep_link.dart';
import 'package:jumping_fitness/notifications/push_service.dart';
import 'package:jumping_fitness/notifications/web_push_prompt.dart';

import 'support/fake_push.dart';
import 'support/fake_studio.dart';
import 'support/fakes.dart';
import 'support/test_app.dart';

const phone = '+79991234567';
final uid = FakeAuthRepository.uidFor(phone);

class Setup {
  Setup() {
    auth = FakeAuthRepository()..signInAs(phone);
    backend = FakeBackend()
      ..putProfile(
        UserProfile(
          uid: uid,
          fullName: 'Анна Смирнова',
          phone: phone,
          role: UserRole.client,
          isAdmin: false,
          createdAt: DateTime.utc(2026, 9, 1),
          monthlyFlower: const MonthlyFlower(
            month: '2026-09',
            flowerId: 'rose',
          ),
        ),
      );
    studio = FakeStudio(uid: uid);
  }

  late final FakeAuthRepository auth;
  late final FakeBackend backend;
  late final FakeStudio studio;
  final push = FakePush();
  final notifications = FakeNotifications();

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildTestApp(
        auth: auth,
        backend: backend,
        studio: studio,
        push: push,
        notifications: notifications,
      ),
    );
    await tester.pumpAndSettle();
  }
}

const changedMessage = PushMessage(
  title: 'Тренировка изменена',
  body: 'Тренировка 29 сентября теперь начинается в 19:00.',
  data: {
    'kind': 'training_changed',
    'trainingId': 't1',
    'date': '2026-09-29',
    'slot': 'evening',
  },
);

void main() {
  group('куда ведёт уведомление', () {
    test('тренировка — в её ячейку; заявка — к заявкам; прочее — домой', () {
      expect(
        DeepLink.fromData(changedMessage.data),
        OpenTrainingCell(
          day: CalendarDay.parse('2026-09-29'),
          slot: DaySlot.evening,
        ),
      );
      expect(
        DeepLink.fromData({'kind': 'trainer_request_new'}),
        isA<OpenTrainerRequests>(),
      );
      expect(
        DeepLink.fromData({'kind': 'subscription_expired'}),
        isA<OpenSubscription>(),
      );
      expect(
        DeepLink.fromData({'kind': 'training_cancelled', 'date': 'кривая'}),
        isA<OpenHome>(),
      );
      expect(DeepLink.fromData(const {}), isA<OpenHome>());
    });
  });

  group('push', () {
    testWidgets(
      'после входа устройство подписывается, при выходе — отписывается',
      (tester) async {
        final s = Setup();
        await s.pump(tester);
        expect(s.push.started, [uid]);

        await tester.tap(find.byTooltip('Выйти'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Выйти'));
        await tester.pumpAndSettle();
        expect(s.push.stopped, [uid]);
        expect(find.text('Вход'), findsOneWidget);
      },
    );

    testWidgets('приложение открыто — баннер с кнопкой «Открыть»', (
      tester,
    ) async {
      final s = Setup();
      s.studio.putTraining(
        id: 't1',
        date: CalendarDay.parse('2026-09-29'),
        slot: DaySlot.evening,
        time: const TimeOfDayHm(19, 0),
      );
      s.studio.putSlot(CalendarDay.parse('2026-09-29'), DaySlot.evening, 't1');
      await s.pump(tester);

      s.push.arriveWhileOpen(changedMessage);
      await tester.pumpAndSettle();
      expect(find.text('Тренировка изменена'), findsOneWidget);
      expect(
        find.text('Тренировка 29 сентября теперь начинается в 19:00.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(find.text('Вторник, 29 сентября'), findsOneWidget);
      expect(find.text('19:00–20:00'), findsOneWidget);
    });

    testWidgets('тап по системному уведомлению открывает ячейку тренировки', (
      tester,
    ) async {
      final s = Setup();
      await s.pump(tester);
      // Пока открыто что-то поверх — переход всё равно с главного экрана.
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();

      s.push.tapInSystemTray(changedMessage);
      await tester.pumpAndSettle();
      expect(find.text('Тема оформления'), findsNothing);
      expect(find.text('Вторник, 29 сентября'), findsOneWidget);
    });
  });

  group('история уведомлений', () {
    testWidgets('счётчик на колокольчике, список, отметка «прочитано»', (
      tester,
    ) async {
      final s = Setup();
      s.notifications
        ..put(
          notification('n1', read: true, title: 'Старое', body: 'Прочитанное.'),
        )
        ..put(
          notification(
            'n2',
            kind: 'subscription_ending_soon',
            title: 'Абонемент скоро закончится',
            body: 'Осталось 3 дня.',
          ),
        )
        ..put(
          notification(
            'n3',
            data: {'date': '2026-09-29', 'slot': 'evening', 'trainingId': 't1'},
          ),
        );
      await s.pump(tester);

      expect(find.byTooltip('Уведомления: новых 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Уведомления: новых 2'));
      await tester.pumpAndSettle();

      expect(find.text('Уведомления'), findsOneWidget);
      expect(find.text('Абонемент скоро закончится'), findsOneWidget);
      expect(find.text('Старое'), findsOneWidget);
      expect(s.notifications.markedRead.toSet(), {'n2', 'n3'});

      // Тап по уведомлению о тренировке — её окно поверх главного экрана.
      await tester.tap(find.text('Тренировка изменена'));
      await tester.pumpAndSettle();
      expect(find.text('Вторник, 29 сентября'), findsOneWidget);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Уведомления'), findsOneWidget);
    });

    testWidgets('пусто — понятная надпись', (tester) async {
      final s = Setup();
      await s.pump(tester);
      await tester.tap(find.byTooltip('Уведомления'));
      await tester.pumpAndSettle();
      expect(find.text('Уведомлений пока нет.'), findsOneWidget);
    });
  });

  group('веб-версия: подсказка про push', () {
    WebPushHint hint({
      bool isWeb = true,
      bool isIos = true,
      bool standalone = false,
      PushPermission permission = PushPermission.unsupported,
    }) => webPushHintFor(
      isWeb: isWeb,
      isIos: isIos,
      standalone: standalone,
      permission: permission,
    );

    test('iPhone в Safari — сначала «на экран Домой»', () {
      expect(hint(), WebPushHint.installToHomeScreen);
    });

    test('установлено или Android-браузер: не спрашивали — кнопка', () {
      expect(
        hint(standalone: true, permission: PushPermission.notAsked),
        WebPushHint.enable,
      );
      expect(
        hint(isIos: false, permission: PushPermission.notAsked),
        WebPushHint.enable,
      );
    });

    test('уже разрешено, запрещено, не браузер — без подсказки', () {
      expect(hint(permission: PushPermission.granted), WebPushHint.none);
      expect(hint(permission: PushPermission.denied), WebPushHint.none);
      expect(hint(isIos: false), WebPushHint.none);
      expect(
        hint(isWeb: false, permission: PushPermission.notAsked),
        WebPushHint.none,
      );
    });
  });
}
