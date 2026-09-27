import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/models/models.dart';
import 'package:jumping_fitness/screens/trainer/clients_section.dart';

import 'support/fake_studio.dart';
import 'support/fakes.dart';
import 'support/test_app.dart';

const phone = '+79990000077';
final uid = FakeAuthRepository.uidFor(phone);
CalendarDay d(String key) => CalendarDay.parse(key);

// «Сейчас» — понедельник 28.09.2026, 12:00 по Москве (support/test_app.dart).

Finder cell(String day, DaySlot slot) =>
    find.byKey(ValueKey('cell-${day}_${slot.wireName}'));

Finder inDialog(Finder finder) =>
    find.descendant(of: find.byType(AlertDialog).last, matching: finder);

Finder textIn(Finder parent, String text) =>
    find.descendant(of: parent, matching: find.text(text));

UserProfile person(String id, String name, {String? subId}) => UserProfile(
  uid: id,
  fullName: name,
  phone: '+79990000001',
  role: UserRole.client,
  isAdmin: false,
  createdAt: DateTime.utc(2026, 9, 1),
  currentSubscriptionId: subId,
);

Booking bookingOf(Training t, String clientId, String name) => Booking(
  clientId: clientId,
  clientName: name,
  trainingId: t.id!,
  trainingStartAt: t.startAt,
  status: BookingStatus.active,
  subscriptionId: 's-$clientId',
);

class Setup {
  Setup() {
    auth = FakeAuthRepository()..signInAs(phone);
    backend = FakeBackend()
      ..putProfile(
        UserProfile(
          uid: uid,
          fullName: 'Мария Ковалёва',
          phone: phone,
          role: UserRole.trainer,
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

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
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

void main() {
  group('календарь тренера', () {
    testWidgets('места, «+» в пустых, отменённая — пустая, прошлое — «—»', (
      tester,
    ) async {
      final s = Setup();
      final cancelled = s.studio.putTraining(
        id: 'c1',
        date: d('2026-09-30'),
        slot: DaySlot.evening,
        time: const TimeOfDayHm(18, 0),
        status: TrainingStatus.cancelled,
      );
      s.studio
        ..putSlot(d('2026-09-30'), DaySlot.evening, null)
        ..putBooking(cancelled, BookingStatus.trainingCancelled);
      await s.pump(tester);

      expect(
        textIn(cell('2026-09-28', DaySlot.evening), '0/13'),
        findsOneWidget,
      );
      expect(textIn(cell('2026-09-29', DaySlot.morning), '+'), findsOneWidget);
      // Отменённая: у тренера пустая ячейка, не «Отменено» (ТЗ 3.2).
      expect(textIn(cell('2026-09-30', DaySlot.evening), '+'), findsOneWidget);
      expect(find.text('Отменено'), findsNothing);
      expect(textIn(cell('2026-09-27', DaySlot.morning), '—'), findsOneWidget);
    });

    testWidgets('пустая ячейка → новая тренировка со значениями по умолчанию', (
      tester,
    ) async {
      final s = Setup();
      await s.pump(tester);

      await openCell(tester, '2026-09-29', DaySlot.morning);
      expect(find.text('Вторник, 29 сентября'), findsOneWidget);
      expect(inDialog(find.text('08:10')), findsOneWidget);
      expect(inDialog(find.text('60 мин')), findsOneWidget);
      expect(inDialog(find.text('13')), findsOneWidget);

      await tester.tap(inDialog(find.text('Назначить тренировку')));
      await tester.pumpAndSettle();
      expect(s.studio.calls, ['create:2026-09-29_morning:08:10:60:13']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Тренировка назначена.'), findsOneWidget);
      expect(
        textIn(cell('2026-09-29', DaySlot.morning), '0/13'),
        findsOneWidget,
      );
    });

    testWidgets('мест нельзя меньше, чем записано — с предупреждением', (
      tester,
    ) async {
      final s = Setup();
      final t = s.studio.putTraining(
        id: 't1',
        date: d('2026-09-29'),
        slot: DaySlot.evening,
        time: const TimeOfDayHm(19, 0),
        capacity: 4,
        bookedCount: 3,
      );
      s.studio.putSlot(d('2026-09-29'), DaySlot.evening, 't1');
      s.studio.trainingBookings['t1'] = [
        bookingOf(t, 'a', 'Смирнова Анна'),
        bookingOf(t, 'b', 'Петрова Ольга'),
        bookingOf(t, 'c', 'Волкова Ирина'),
      ];
      await s.pump(tester);

      await openCell(tester, '2026-09-29', DaySlot.evening);
      await tester.tap(find.byTooltip('Мест: меньше'));
      await tester.pump();
      expect(inDialog(find.text('3')), findsOneWidget);
      await tester.tap(find.byTooltip('Мест: меньше'));
      await tester.pump();
      expect(find.textContaining('Нельзя поставить меньше 3'), findsOneWidget);
      expect(inDialog(find.text('3')), findsOneWidget);

      await tester.tap(inDialog(find.text('Сохранить изменения')));
      await tester.pumpAndSettle();
      expect(s.studio.calls, ['update:t1:null:null:3']);
    });

    testWidgets('список записавшихся свёрнут; мусорка — с подтверждением', (
      tester,
    ) async {
      final s = Setup();
      final t = s.studio.putTraining(
        id: 't1',
        date: d('2026-09-29'),
        slot: DaySlot.evening,
        time: const TimeOfDayHm(19, 0),
        bookedCount: 2,
      );
      s.studio.putSlot(d('2026-09-29'), DaySlot.evening, 't1');
      s.studio.clients['a'] = person('a', 'Смирнова Анна', subId: 's-a');
      s.studio.subscriptions['s-a'] = subscription(
        id: 's-a',
        clientId: 'a',
        start: d('2026-09-15'),
        end: d('2026-10-14'),
        left: 5,
      );
      s.studio.trainingBookings['t1'] = [
        bookingOf(t, 'a', 'Смирнова Анна'),
        bookingOf(t, 'b', 'Петрова Ольга'),
      ];
      await s.pump(tester);

      await openCell(tester, '2026-09-29', DaySlot.evening);
      // Свёрнут по умолчанию.
      expect(inDialog(find.text('Смирнова Анна')), findsNothing);
      await tester.tap(find.text('Записаны: 2 человека'));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Смирнова Анна')), findsOneWidget);
      expect(
        inDialog(find.text('Осталось 17 дней · 5 тренировок')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Удалить с тренировки').first);
      await tester.pumpAndSettle();
      expect(find.text('Удалить с тренировки?'), findsOneWidget);
      await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Удалить')));
      await tester.pumpAndSettle();
      // Сортировка по алфавиту: первая — Петрова.
      expect(s.studio.calls, ['remove:t1:b']);
      expect(inDialog(find.text('Петрова Ольга')), findsNothing);
    });

    testWidgets('отмена тренировки — подтверждение, вызов сервера', (
      tester,
    ) async {
      final s = Setup();
      await s.pump(tester);

      await openCell(tester, '2026-09-28', DaySlot.evening);
      await tester.tap(inDialog(find.text('Отменить тренировку')));
      await tester.pumpAndSettle();
      expect(find.text('Отменить тренировку?'), findsOneWidget);
      await tester.tap(
        inDialog(find.widgetWithText(FilledButton, 'Отменить тренировку')),
      );
      await tester.pumpAndSettle();
      // Тренировка по расписанию без документа — по ячейке.
      expect(s.studio.calls, ['cancelTraining:2026-09-28_evening']);
      expect(textIn(cell('2026-09-28', DaySlot.evening), '+'), findsOneWidget);
    });

    testWidgets('началась — только просмотр', (tester) async {
      final s = Setup();
      await s.pump(tester);
      // Утро понедельника уже прошло.
      await openCell(tester, '2026-09-28', DaySlot.morning);
      expect(find.textContaining('уже началась'), findsOneWidget);
      expect(find.text('Сохранить изменения'), findsNothing);
      expect(find.text('Отменить тренировку'), findsNothing);
    });
  });

  group('профиль и клиенты', () {
    Setup withClients() {
      final s = Setup();
      s.studio.clients
        ..['a'] = person('a', 'Смирнова Анна', subId: 's-a')
        ..['b'] = person('b', 'Ёлкина Ольга', subId: 's-b')
        ..['c'] = person('c', 'Волкова Ирина', subId: 's-c');
      s.studio.subscriptions
        ..['s-a'] = subscription(
          id: 's-a',
          clientId: 'a',
          start: d('2026-09-15'),
          end: d('2026-10-14'),
          left: 6,
        )
        ..['s-b'] = subscription(
          id: 's-b',
          clientId: 'b',
          start: d('2026-09-01'),
          end: d('2026-09-30'),
          left: 8,
        )
        ..['s-c'] = subscription(
          id: 's-c',
          clientId: 'c',
          start: d('2026-09-20'),
          end: d('2026-10-19'),
          left: 1,
        );
      return s;
    }

    List<String> order(WidgetTester tester) => [
      for (final row in tester.widgetList<ClientRow>(find.byType(ClientRow)))
        row.client.profile.fullName,
    ];

    testWidgets('плашка «Тренер» рядом с ФИО', (tester) async {
      final s = Setup();
      await s.pump(tester);
      expect(find.text('Мария Ковалёва'), findsOneWidget);
      expect(find.text('Тренер'), findsOneWidget);
    });

    testWidgets('после закрытия окна фокус не возвращается в поиск', (
      tester,
    ) async {
      final s = withClients();
      await s.pump(tester);
      final search = find.byType(TextField);
      await tester.ensureVisible(search);
      await tester.tap(search);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // Открыли окно ячейки и закрыли тапом снаружи.
      await openCell(tester, '2026-09-28', DaySlot.evening);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('сортировка, переключатель, поиск на лету', (tester) async {
      final s = withClients();
      await s.pump(tester);
      await tester.ensureVisible(find.text('Поиск по ФИО'));

      expect(order(tester), ['Волкова Ирина', 'Смирнова Анна', 'Ёлкина Ольга']);
      await tester.tap(find.text('По дням'));
      await tester.pumpAndSettle();
      expect(order(tester), ['Ёлкина Ольга', 'Смирнова Анна', 'Волкова Ирина']);

      await tester.enterText(find.byType(TextField), 'елк');
      await tester.pumpAndSettle();
      expect(order(tester), ['Ёлкина Ольга']);
      expect(find.text('Осталось 8 тренировок · 3 дня'), findsOneWidget);
    });

    testWidgets('карточка клиента → продление с умолчаниями из ТЗ 7', (
      tester,
    ) async {
      final s = withClients();
      await s.pump(tester);
      await tester.ensureVisible(find.text('Смирнова Анна'));
      await tester.tap(find.text('Смирнова Анна'));
      await tester.pumpAndSettle();

      expect(
        inDialog(find.text('Абонемент с 15 сентября по 14 октября')),
        findsOneWidget,
      );
      expect(inDialog(find.text('Осталось 17 дней')), findsOneWidget);
      await tester.tap(inDialog(find.text('Продлить абонемент')));
      await tester.pumpAndSettle();

      expect(find.text('Продление абонемента'), findsOneWidget);
      expect(inDialog(find.text('28 сентября 2026')), findsOneWidget);
      expect(inDialog(find.text('27 октября 2026')), findsOneWidget);
      expect(inDialog(find.text('11')), findsOneWidget);
      expect(inDialog(find.text('3')), findsOneWidget);

      await tester.tap(inDialog(find.text('Обновить')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Оформить')));
      await tester.pumpAndSettle();

      final renew = s.studio.lastRenew!;
      expect(renew.clientId, 'a');
      expect(renew.start, d('2026-09-28'));
      expect(renew.end, d('2026-10-27'));
      expect(renew.trainings, 11);
      expect(renew.freezeLimitDays, 3);
      expect(find.text('Абонемент оформлен: Смирнова Анна.'), findsOneWidget);
    });
  });
}
