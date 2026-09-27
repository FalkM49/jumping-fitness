import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/client/calendar_cells.dart';
import 'package:jumping_fitness/models/models.dart';
import 'package:jumping_fitness/trainer/client_list.dart';

import 'support/fake_studio.dart';

CalendarDay d(String key) => CalendarDay.parse(key);
final today = d('2026-09-28');
final now = DateTime.utc(2026, 9, 28, 9);

UserProfile client(
  String uid,
  String name, {
  String? subId,
  bool isAdmin = false,
}) => UserProfile(
  uid: uid,
  fullName: name,
  phone: '+79990000000',
  role: UserRole.client,
  isAdmin: isAdmin,
  createdAt: null,
  currentSubscriptionId: subId,
);

void main() {
  group('русский алфавит', () {
    test('«ё» сразу после «е», а не в конце', () {
      final names = ['Яковлева', 'Ёлкина', 'Ежова', 'Жукова', 'Абрамова']
        ..sort(compareRussian);
      expect(names, ['Абрамова', 'Ежова', 'Ёлкина', 'Жукова', 'Яковлева']);
    });

    test('без учёта регистра, короткое раньше длинного', () {
      expect(compareRussian('анна', 'Анна'), 0);
      expect(compareRussian('Анна', 'Анна Смирнова'), lessThan(0));
    });
  });

  group('список клиентов', () {
    late List<ClientSummary> all;

    setUp(() {
      all = summarizeClients(
        clients: [
          client('a', 'Смирнова Анна', subId: 's-a'),
          client('b', 'Ёлкина Ольга', subId: 's-b'),
          client('c', 'Волкова Ирина', subId: 's-c'),
          client('d', 'Новикова Дарья'),
          client('dev', 'Разработчик', isAdmin: true),
        ],
        currentSubscriptions: [
          subscription(
            id: 's-a',
            clientId: 'a',
            start: d('2026-09-15'),
            end: d('2026-10-14'),
            left: 3,
          ),
          subscription(
            id: 's-b',
            clientId: 'b',
            start: d('2026-09-01'),
            end: d('2026-09-30'),
            left: 3,
          ),
          subscription(
            id: 's-c',
            clientId: 'c',
            start: d('2026-09-20'),
            end: d('2026-10-19'),
            left: 9,
          ),
        ],
        today: today,
      );
    });

    List<String> names(List<ClientSummary> list) => [
      for (final c in list) c.profile.fullName,
    ];

    test('администратор-разработчик в список клиентов не попадает', () {
      expect(all, hasLength(4));
    });

    test('по тренировкам: меньше — выше, при равенстве — по алфавиту', () {
      expect(names(sortClients(all, ClientSort.trainings)), [
        'Новикова Дарья', // без абонемента — 0
        'Ёлкина Ольга', // 3
        'Смирнова Анна', // 3
        'Волкова Ирина', // 9
      ]);
    });

    test('по дням: меньше дней — выше', () {
      expect(names(sortClients(all, ClientSort.days)), [
        'Новикова Дарья', // 0
        'Ёлкина Ольга', // 3 дня (по 30.09)
        'Смирнова Анна', // 17
        'Волкова Ирина', // 22
      ]);
    });

    test('поиск по ФИО на лету: регистр, «ё» и порядок слов не важны', () {
      expect(names(searchClients(all, 'елкина')), ['Ёлкина Ольга']);
      expect(names(searchClients(all, 'ИРИНА вол')), ['Волкова Ирина']);
      expect(searchClients(all, '  '), hasLength(4));
      expect(searchClients(all, 'петрова'), isEmpty);
    });

    test('истёкший абонемент — 0 тренировок и 0 дней', () {
      final expired = ClientSummary(
        profile: client('x', 'Икс', subId: 's-x'),
        subscription: subscription(
          id: 's-x',
          clientId: 'x',
          start: d('2026-08-01'),
          end: d('2026-08-30'),
          left: 4,
        ),
        today: today,
      );
      expect(expired.trainingsLeft, 0);
      expect(expired.daysLeft, 0);
      expect(expired.isActive, isFalse);
    });
  });

  group('ячейки календаря тренера', () {
    final cancelled = Training(
      id: 'c1',
      date: d('2026-09-30'),
      slot: DaySlot.evening,
      startTime: const TimeOfDayHm(18, 0),
      startAt: d('2026-09-30').atStudioTime(18, 0),
      durationMinutes: 60,
      capacity: 13,
      bookedCount: 0,
      status: TrainingStatus.cancelled,
      source: TrainingSource.defaultSchedule,
    );
    final data = CalendarData(
      trainings: [cancelled],
      slots: [
        CalendarSlot(
          slotKey: '2026-09-30_evening',
          date: d('2026-09-30'),
          slot: DaySlot.evening,
          activeTrainingId: null,
          overridesDefault: true,
        ),
      ],
      myBookings: const [],
      settings: AppSettings.fallback,
    );

    test('отменённая тренировка у тренера — обычная пустая ячейка', () {
      expect(
        data.cellFor(
          CalendarMode.trainer,
          d('2026-09-30'),
          DaySlot.evening,
          now,
        ),
        isA<EmptyCell>(),
      );
    });

    test('тренировка по расписанию видна тренеру с местами', () {
      final cell =
          data.cellFor(
                CalendarMode.trainer,
                d('2026-09-28'),
                DaySlot.evening,
                now,
              )
              as TrainingCell;
      expect(cell.training.capacity, 13);
      expect(cell.isBooked, isFalse);
    });
  });
}
