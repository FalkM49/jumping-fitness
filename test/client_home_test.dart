import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/models/models.dart';
import 'package:jumping_fitness/screens/client/subscription_card.dart';
import 'package:jumping_fitness/services/cloud_functions.dart';
import 'package:jumping_fitness/widgets/flower_art.dart';

import 'support/fake_studio.dart';
import 'support/fakes.dart';
import 'support/test_app.dart';

const phone = '+79991234567';
final uid = FakeAuthRepository.uidFor(phone);
CalendarDay d(String key) => CalendarDay.parse(key);

// «Сейчас» — понедельник 28.09.2026, 12:00 по Москве (support/test_app.dart).
final today = d('2026-09-28');

Finder cell(String day, DaySlot slot) =>
    find.byKey(ValueKey('cell-${day}_${slot.wireName}'));

Finder inDialog(Finder finder) =>
    find.descendant(of: find.byType(AlertDialog).last, matching: finder);

class Setup {
  Setup({
    bool withSubscription = true,
    bool withFlower = true,
    Subscription? sub,
  }) {
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
          currentSubscriptionId: withSubscription ? 'sub' : null,
          monthlyFlower: withFlower
              ? const MonthlyFlower(month: '2026-09', flowerId: 'peony')
              : null,
        ),
      );
    studio = FakeStudio(uid: uid)
      ..flowers['peony'] = const Flower(
        id: 'peony',
        name: 'Пион',
        description: 'Пышный садовый цветок с многослойными лепестками',
        meaning: 'Процветание, благополучие',
        image: 'assets/flowers/peony.png',
        order: 1,
      );
    if (withSubscription) {
      studio.subscriptions['sub'] =
          sub ??
          subscription(
            clientId: uid,
            start: d('2026-09-15'),
            end: d('2026-10-14'),
          );
    }
  }

  late final FakeAuthRepository auth;
  late final FakeBackend backend;
  late final FakeStudio studio;

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildTestApp(auth: auth, backend: backend, studio: studio),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> openCell(WidgetTester tester, String day, DaySlot slot) async {
  await tester.ensureVisible(cell(day, slot));
  await tester.tap(cell(day, slot));
  await tester.pumpAndSettle();
}

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('календарь', () {
    testWidgets('сегодня, месяц, утро/вечер и состояния ячеек', (tester) async {
      final s = Setup();
      // Вторник: ручная тренировка, клиент записан.
      final tue = s.studio.putTraining(
        id: 'm1',
        date: d('2026-09-29'),
        slot: DaySlot.morning,
        time: const TimeOfDayHm(9, 30),
        bookedCount: 3,
      );
      s.studio
        ..putSlot(d('2026-09-29'), DaySlot.morning, 'm1')
        ..putBooking(tue, BookingStatus.active);
      // Среда вечер: тренер отменил тренировку, клиент был записан.
      final wed = s.studio.putTraining(
        id: 'c1',
        date: d('2026-09-30'),
        slot: DaySlot.evening,
        time: const TimeOfDayHm(18, 0),
        status: TrainingStatus.cancelled,
      );
      s.studio
        ..putSlot(d('2026-09-30'), DaySlot.evening, null)
        ..putBooking(wed, BookingStatus.trainingCancelled);
      await s.pump(tester);

      expect(find.text('Сегодня'), findsOneWidget);
      expect(find.text('Сентябрь'), findsWidgets);
      expect(find.text('Утро'), findsOneWidget);
      expect(find.text('Вечер'), findsOneWidget);

      Finder textIn(Finder c, String text) =>
          find.descendant(of: c, matching: find.text(text));
      // Утро понедельника уже началось, вечер — по расписанию, свободен.
      expect(
        textIn(cell('2026-09-28', DaySlot.morning), 'прошла'),
        findsOneWidget,
      );
      expect(
        textIn(cell('2026-09-28', DaySlot.evening), '0/13'),
        findsOneWidget,
      );
      expect(
        textIn(cell('2026-09-29', DaySlot.morning), 'вы записаны'),
        findsOneWidget,
      );
      expect(
        textIn(cell('2026-09-30', DaySlot.evening), 'Отменено'),
        findsOneWidget,
      );
      expect(textIn(cell('2026-09-29', DaySlot.evening), '—'), findsOneWidget);
    });

    testWidgets('запись и отмена через окно тренировки', (tester) async {
      final s = Setup();
      await s.pump(tester);

      await openCell(tester, '2026-09-28', DaySlot.evening);
      expect(find.text('Понедельник, 28 сентября'), findsOneWidget);
      expect(find.text('18:00–19:00'), findsOneWidget);
      expect(find.text('13 из 13'), findsOneWidget);

      await tester.tap(inDialog(find.text('Записаться')));
      await tester.pumpAndSettle();
      // Тренировки по расписанию ещё нет в базе — сервер получает день и строку.
      expect(s.studio.calls, ['book:2026-09-28_evening']);
      expect(find.text('Вы записаны на эту тренировку.'), findsOneWidget);
      expect(inDialog(find.text('Отменить запись')), findsOneWidget);

      await tester.tap(inDialog(find.text('Отменить запись')));
      await tester.pumpAndSettle();
      expect(find.text('Отменить запись?'), findsOneWidget);
      await tester.tap(
        inDialog(find.widgetWithText(FilledButton, 'Отменить запись')),
      );
      await tester.pumpAndSettle();
      expect(s.studio.calls.last, 'cancel:default_2026-09-28_evening');
      expect(inDialog(find.text('Записаться')), findsOneWidget);

      // Окно закрывается тапом вне его (ТЗ 9).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('меньше 3 часов до начала — отмена недоступна, (i) объясняет', (
      tester,
    ) async {
      final s = Setup();
      final soon = s.studio.putTraining(
        id: 'soon',
        date: today,
        slot: DaySlot.evening,
        time: const TimeOfDayHm(14, 30),
      );
      s.studio
        ..putSlot(today, DaySlot.evening, 'soon')
        ..putBooking(soon, BookingStatus.active);
      await s.pump(tester);

      await openCell(tester, '2026-09-28', DaySlot.evening);
      final cancel = tester.widget<OutlinedButton>(
        inDialog(find.widgetWithText(OutlinedButton, 'Отменить запись')),
      );
      expect(cancel.onPressed, isNull);

      await tester.tap(find.byTooltip('Почему недоступно'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Отмена уже недоступна'), findsOneWidget);
    });

    testWidgets('без абонемента записаться нельзя — с причиной', (
      tester,
    ) async {
      final s = Setup(withSubscription: false);
      await s.pump(tester);

      await openCell(tester, '2026-09-28', DaySlot.evening);
      final book = tester.widget<FilledButton>(
        inDialog(find.widgetWithText(FilledButton, 'Записаться')),
      );
      expect(book.onPressed, isNull);
      await tester.tap(find.byTooltip('Почему недоступно'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Нет действующего абонемента'),
        findsOneWidget,
      );
      expect(s.studio.calls, isEmpty);
    });

    testWidgets('отказ сервера показывается в окне', (tester) async {
      final s = Setup();
      await s.pump(tester);
      s.studio.nextFailure = const CloudFunctionFailure(
        'Свободных мест нет.',
        'failed-precondition',
        'full',
      );

      await openCell(tester, '2026-09-28', DaySlot.evening);
      await tester.tap(inDialog(find.text('Записаться')));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Свободных мест нет.')), findsOneWidget);
    });
  });

  group('профиль', () {
    testWidgets('«В этом месяце ты:», цветок и окно с его значением', (
      tester,
    ) async {
      final s = Setup();
      await s.pump(tester);
      await scrollTo(tester, find.text('Анна Смирнова'));

      expect(find.text('В этом месяце ты:'), findsOneWidget);
      await tester.tap(find.byType(FlowerArt).first);
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Пион')), findsOneWidget);
      expect(inDialog(find.text('Процветание, благополучие')), findsOneWidget);
    });

    testWidgets('нет цветка на этот месяц — просим сервер назначить', (
      tester,
    ) async {
      final s = Setup(withFlower: false);
      await s.pump(tester);
      expect(s.studio.ensureFlowerCalls, 1);
    });
  });

  group('абонемент', () {
    testWidgets('статус, срок, остаток дней, крупный счётчик, заморозка', (
      tester,
    ) async {
      final s = Setup();
      await s.pump(tester);
      await scrollTo(tester, find.text('Заморозить абонемент'));

      expect(find.text('Активен'), findsOneWidget);
      expect(find.text('С 15 сентября по 14 октября'), findsOneWidget);
      expect(find.text('Осталось 17 дней'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SubscriptionCard),
          matching: find.text('8'),
        ),
        findsOneWidget,
      );
      expect(find.text('тренировок осталось'), findsOneWidget);

      await tester.tap(find.text('Заморозить абонемент'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Больше'));
      await tester.pump();
      expect(inDialog(find.text('2')), findsOneWidget);
      await tester.tap(
        inDialog(find.widgetWithText(FilledButton, 'Заморозить')),
      );
      await tester.pumpAndSettle();
      expect(s.studio.frozenDays, 2);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('тренировки закончились и срок на исходе — плашка и баннер', (
      tester,
    ) async {
      final s = Setup(
        sub: subscription(
          clientId: uid,
          start: d('2026-09-01'),
          end: d('2026-09-30'),
          left: 0,
        ),
      );
      await s.pump(tester);

      expect(
        find.textContaining('Абонемент заканчивается через 3 дня'),
        findsOneWidget,
      );
      await scrollTo(
        tester,
        find.text('Абонемент закончился — продлите у тренера'),
      );
      expect(
        find.descendant(
          of: find.byType(SubscriptionCard),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('срок истёк — тренировки сгорели, баннер и статус', (
      tester,
    ) async {
      final s = Setup(
        sub: subscription(
          clientId: uid,
          start: d('2026-08-20'),
          end: d('2026-09-20'),
          left: 0,
          burned: 3,
          expiredAt: DateTime.utc(2026, 9, 20, 21, 5),
        ),
      );
      await s.pump(tester);

      expect(
        find.textContaining('оставшиеся тренировки сгорели'),
        findsOneWidget,
      );
      await scrollTo(tester, find.text('Неактивен'));
      expect(find.text('Заморозить абонемент'), findsNothing);
    });

    testWidgets('заморозка уже использована — кнопка неактивна с пояснением', (
      tester,
    ) async {
      final s = Setup(
        sub: subscription(
          clientId: uid,
          start: d('2026-09-15'),
          end: d('2026-10-17'),
          freeze: SubscriptionFreeze(
            startDate: d('2026-09-20'),
            endDate: d('2026-09-22'),
            days: 3,
          ),
        ),
      );
      await s.pump(tester);
      await scrollTo(tester, find.textContaining('Заморозка использована'));
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Заморозить абонемент'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });
}
