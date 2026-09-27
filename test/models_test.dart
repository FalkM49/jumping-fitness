import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/models/firestore_parsing.dart';
import 'package:jumping_fitness/models/models.dart';

Timestamp ts(String iso) => Timestamp.fromDate(DateTime.parse(iso));

Matcher formatErrorMentioning(String text) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  group('CalendarDay', () {
    test('ключ YYYY-MM-DD туда и обратно', () {
      final day = CalendarDay.parse('2026-09-05');
      expect(day.toKey(), '2026-09-05');
      expect(day.monthKey, '2026-09');
      expect(day.weekday, DateTime.saturday);
    });

    test('несуществующие и кривые даты отклоняются', () {
      expect(() => CalendarDay.parse('2026-02-30'), throwsFormatException);
      expect(() => CalendarDay.parse('2026-9-5'), throwsFormatException);
      expect(() => CalendarDay.parse(''), throwsFormatException);
    });

    test('день считается по Москве, а не по часовому поясу телефона', () {
      // 22:30 UTC = 01:30 следующего дня в Москве.
      expect(
        CalendarDay.ofInstant(DateTime.utc(2026, 9, 27, 22, 30)).toKey(),
        '2026-09-28',
      );
      expect(
        CalendarDay.ofInstant(DateTime.utc(2026, 9, 27, 20, 59)).toKey(),
        '2026-09-27',
      );
    });

    test('время студии → абсолютный момент', () {
      final start = CalendarDay.parse('2026-09-28').atStudioTime(8, 10);
      expect(start, DateTime.utc(2026, 9, 28, 5, 10));
    });

    test('арифметика дней через границу месяца и года', () {
      expect(CalendarDay.parse('2026-09-30').addDays(1).toKey(), '2026-10-01');
      expect(CalendarDay.parse('2026-12-31').addDays(1).toKey(), '2027-01-01');
      expect(
        CalendarDay.parse(
          '2026-10-01',
        ).daysSince(CalendarDay.parse('2026-09-01')),
        30,
      );
    });

    test('сравнение и попадание в отрезок', () {
      final a = CalendarDay.parse('2026-09-01');
      final b = CalendarDay.parse('2026-09-30');
      expect(CalendarDay.parse('2026-09-01').isWithin(a, b), isTrue);
      expect(CalendarDay.parse('2026-09-30').isWithin(a, b), isTrue);
      expect(CalendarDay.parse('2026-10-01').isWithin(a, b), isFalse);
      expect(a, CalendarDay(2026, 9, 1));
    });
  });

  group('DaySlot и TimeOfDayHm', () {
    test('ключ ячейки', () {
      expect(
        slotKeyOf(CalendarDay.parse('2026-09-28'), DaySlot.evening),
        '2026-09-28_evening',
      );
      expect(DaySlot.fromWire('morning'), DaySlot.morning);
      expect(() => DaySlot.fromWire('night'), throwsFormatException);
    });

    test('время HH:mm', () {
      expect(TimeOfDayHm.parse('08:10').format(), '08:10');
      expect(TimeOfDayHm.parse('18:00').minutesOfDay, 18 * 60);
      expect(() => TimeOfDayHm.parse('8:10'), throwsFormatException);
      expect(() => TimeOfDayHm.parse('24:00'), throwsFormatException);
    });

    test('граница утра и вечера — 14:00', () {
      expect(DaySlot.ofTime(const TimeOfDayHm(13, 59)), DaySlot.morning);
      expect(DaySlot.ofTime(const TimeOfDayHm(14, 0)), DaySlot.evening);
      expect(DaySlot.morning.admits(const TimeOfDayHm(8, 10)), isTrue);
      expect(DaySlot.morning.admits(const TimeOfDayHm(15, 0)), isFalse);
      expect(DaySlot.evening.admits(const TimeOfDayHm(18, 0)), isTrue);
    });
  });

  group('FirestoreReader', () {
    final r = FirestoreReader('x/1', {
      'a': 13.0,
      'b': 13.7,
      'c': double.nan,
      'd': -1,
    });

    test('целое 13.0 принимается, дробное и NaN — ошибка с путём', () {
      expect(r.integer('a'), 13);
      expect(() => r.integer('b'), formatErrorMentioning('x/1: поле «b»'));
      expect(() => r.integer('c'), formatErrorMentioning('x/1: поле «c»'));
      expect(() => r.integerOr('b', 0), throwsFormatException);
    });

    test('нижняя граница', () {
      expect(
        () => r.integerAtLeast('d', 0),
        formatErrorMentioning('не меньше 0'),
      );
      expect(r.integerAtLeastOr('missing', 1, 5), 5);
    });

    test('необязательная строка с разбором', () {
      final reader = FirestoreReader('x/1', {'t': '8:10'});
      expect(reader.optionalParsed('missing', TimeOfDayHm.parse), isNull);
      expect(
        () => reader.optionalParsed('t', TimeOfDayHm.parse),
        formatErrorMentioning('x/1: поле «t»'),
      );
    });
  });

  group('UserProfile', () {
    Map<String, Object?> data({
      Object? role = 'client',
      bool isAdmin = false,
    }) => {
      'fullName': 'Анна Смирнова',
      'phone': '+79990000001',
      'role': role,
      'isAdmin': isAdmin,
      'createdAt': ts('2026-09-01T10:00:00Z'),
    };

    test('читается из документа', () {
      final p = UserProfile.fromMap('anna', data());
      expect(p.fullName, 'Анна Смирнова');
      expect(p.role, UserRole.client);
      expect(p.isStaff, isFalse);
      expect(p.currentSubscriptionId, isNull);
      expect(p.recentFlowerIds, isEmpty);
    });

    test('тренер и админ — staff', () {
      expect(UserProfile.fromMap('m', data(role: 'trainer')).isStaff, isTrue);
      expect(UserProfile.fromMap('d', data(isAdmin: true)).isStaff, isTrue);
    });

    test('неизвестная роль — ошибка с путём документа', () {
      expect(
        () => UserProfile.fromMap('x', data(role: 'boss')),
        formatErrorMentioning('users/x'),
      );
    });

    test('данные регистрации — ровно те поля, что пропускают правила', () {
      final d = UserProfile.registrationData(
        fullName: '  Анна Смирнова ',
        phone: '+79990000001',
      );
      expect(d.keys.toSet(), {
        'fullName',
        'phone',
        'role',
        'isAdmin',
        'createdAt',
      });
      expect(d['fullName'], 'Анна Смирнова');
      expect(d['role'], 'client');
      expect(d['isAdmin'], isFalse);
    });

    test('проверка ФИО совпадает с правилами', () {
      expect(UserProfile.isValidFullName('Анна-Мария Ёлкина'), isTrue);
      expect(UserProfile.isValidFullName('Ян'), isFalse);
      expect(UserProfile.isValidFullName('Ян '), isFalse);
      expect(UserProfile.isValidFullName(' Анна\nБ'), isFalse);
      expect(UserProfile.isValidFullName('Анна\nСмирнова'), isFalse);
      expect(UserProfile.isValidFullName('Анна\tСмирнова'), isFalse);
      expect(UserProfile.isValidFullName('Я' * 100), isTrue);
      expect(UserProfile.isValidFullName('Я' * 101), isFalse);
    });
  });

  group('TrainerRequest', () {
    test('данные заявки — ровно те поля, что пропускают правила', () {
      final d = TrainerRequest.creationData(
        uid: 'u1',
        fullName: 'Мария Ковалёва',
        phone: '+79990000003',
      );
      expect(d.keys.toSet(), {
        'uid',
        'fullName',
        'phone',
        'status',
        'createdAt',
      });
      expect(d['status'], 'pending');
    });

    test('читается из документа', () {
      final r = TrainerRequest.fromMap('u1', {
        'uid': 'u1',
        'fullName': 'Мария Ковалёва',
        'phone': '+79990000003',
        'status': 'approved',
        'createdAt': ts('2026-09-01T10:00:00Z'),
      });
      expect(r.status, TrainerRequestStatus.approved);
    });
  });

  group('AppSettings', () {
    test('пустой документ → значения из ТЗ', () {
      final s = AppSettings.fromMap(const {});
      expect(s.training.weekdays, {1, 3, 5});
      expect(s.training.morningTime, const TimeOfDayHm(8, 10));
      expect(s.training.eveningTime, const TimeOfDayHm(18, 0));
      expect(s.training.durationMinutes, 60);
      expect(s.training.capacity, 13);
      expect(s.subscription.durationDays, 30);
      expect(s.subscription.trainings, 11);
      expect(s.subscription.freezeLimitDays, 3);
      expect(s.cancelWindowHours, 3);
      expect(s.endingSoonDays, 5);
    });

    test('сид settings_defaults.json совпадает со значениями из кода', () {
      final json =
          jsonDecode(
                File('firebase/seed/settings_defaults.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      final s = AppSettings.fromMap(json);
      const f = AppSettings.fallback;
      expect(s.training.weekdays, f.training.weekdays);
      expect(s.training.morningTime, f.training.morningTime);
      expect(s.training.eveningTime, f.training.eveningTime);
      expect(s.training.capacity, f.training.capacity);
      expect(s.subscription.trainings, f.subscription.trainings);
      expect(s.subscription.freezeLimitDays, f.subscription.freezeLimitDays);
      expect(s.cancelWindowHours, f.cancelWindowHours);
    });

    test(
      'частично заполненный документ дополняется значениями по умолчанию',
      () {
        final s = AppSettings.fromMap({
          'training': {'capacity': 15, 'morningTime': '09:00'},
        });
        expect(s.training.capacity, 15);
        expect(s.training.morningTime, const TimeOfDayHm(9, 0));
        expect(s.training.eveningTime, const TimeOfDayHm(18, 0));
        expect(s.subscription.trainings, 11);
      },
    );

    test('битое время — ошибка с путём и полем', () {
      expect(
        () => AppSettings.fromMap({
          'training': {'eveningTime': '8:10'},
        }),
        formatErrorMentioning('settings/defaults.training: поле «eveningTime»'),
      );
    });

    test('время по умолчанию обязано попадать в свою строку сетки', () {
      expect(
        () => AppSettings.fromMap({
          'training': {'morningTime': '15:00'},
        }),
        formatErrorMentioning('поле «morningTime»'),
      );
      expect(
        () => AppSettings.fromMap({
          'training': {'eveningTime': '09:00'},
        }),
        formatErrorMentioning('поле «eveningTime»'),
      );
    });

    test('недопустимые числа отклоняются', () {
      expect(
        () => AppSettings.fromMap({
          'training': {'capacity': 0},
        }),
        formatErrorMentioning('поле «capacity»'),
      );
      expect(
        () => AppSettings.fromMap({
          'training': {'capacity': 13.7},
        }),
        formatErrorMentioning('поле «capacity»'),
      );
      expect(
        () => AppSettings.fromMap({
          'subscription': {'freezeLimitDays': -1},
        }),
        formatErrorMentioning('поле «freezeLimitDays»'),
      );
    });
  });

  group('Flower и сид цветков', () {
    test('14 уникальных цветков, без дубля пиона', () {
      final list =
          (jsonDecode(File('firebase/seed/flowers.json').readAsStringSync())
                  as List<Object?>)
              .cast<Map<String, Object?>>();

      final flowers = [
        for (final item in list) Flower.fromMap(item['id']! as String, item),
      ];
      expect(flowers, hasLength(14));
      expect(flowers.map((f) => f.id).toSet(), hasLength(14));
      expect(flowers.map((f) => f.name).toSet(), hasLength(14));
      expect(flowers.where((f) => f.name.contains('Пион')), hasLength(1));
      for (final f in flowers) {
        expect(f.meaning, isNotEmpty, reason: f.id);
        expect(f.image, 'assets/flowers/${f.id}.png');
      }
    });
  });

  group('Training', () {
    final data = {
      'slotKey': '2026-09-28_morning',
      'date': '2026-09-28',
      'slot': 'morning',
      'startTime': '08:10',
      'startAt': ts('2026-09-28T05:10:00Z'),
      'durationMinutes': 60,
      'capacity': 13,
      'bookedCount': 5,
      'status': 'scheduled',
      'source': 'default',
    };

    test('читается из документа', () {
      final t = Training.fromMap('t1', data);
      expect(t.slotKey, '2026-09-28_morning');
      expect(t.freePlaces, 8);
      expect(t.isFull, isFalse);
      expect(t.isVirtual, isFalse);
      expect(t.endAt, DateTime.utc(2026, 9, 28, 6, 10));
    });

    test('виртуальная тренировка по умолчанию', () {
      final t = Training.virtualDefault(
        date: CalendarDay.parse('2026-09-28'),
        slot: DaySlot.evening,
        defaults: AppSettings.fallback.training,
      );
      expect(t.isVirtual, isTrue);
      expect(t.startTime.format(), '18:00');
      expect(t.startAt, DateTime.utc(2026, 9, 28, 15));
      expect(t.capacity, 13);
      expect(t.freePlaces, 13);
    });

    test('битое поле — понятная ошибка', () {
      expect(
        () => Training.fromMap('t1', {...data, 'capacity': 'много'}),
        formatErrorMentioning('trainings/t1: поле «capacity»'),
      );
      expect(
        () => Training.fromMap('t1', {...data, 'startTime': '8:10'}),
        formatErrorMentioning('trainings/t1: поле «startTime»'),
      );
    });

    test('отрицательные места — понятная ошибка, а не падение', () {
      expect(
        () => Training.fromMap('t1', {...data, 'capacity': -1}),
        formatErrorMentioning('trainings/t1: поле «capacity»'),
      );
      expect(
        () => Training.fromMap('t1', {...data, 'durationMinutes': 0}),
        formatErrorMentioning('поле «durationMinutes»'),
      );
    });

    test('переполненная тренировка: свободных мест 0', () {
      final t = Training.fromMap('t1', {
        ...data,
        'capacity': 0,
        'bookedCount': 2,
      });
      expect(t.freePlaces, 0);
      expect(t.isFull, isTrue);
    });
  });

  group('Booking', () {
    test('статусы совпадают со схемой', () {
      expect(BookingStatus.values.map((s) => s.wireName), [
        'active',
        'cancelled_by_client',
        'removed_by_trainer',
        'training_cancelled',
      ]);
    });

    test('повторная запись — только после собственной отмены', () {
      Booking booking(String status) => Booking.fromMap('t1', 'anna', {
        'clientId': 'anna',
        'clientName': 'Анна Смирнова',
        'trainingStartAt': ts('2026-09-28T05:10:00Z'),
        'status': status,
        'subscriptionId': 's1',
      });
      expect(booking('cancelled_by_client').allowsRebooking, isTrue);
      expect(booking('removed_by_trainer').allowsRebooking, isFalse);
      expect(booking('active').isActive, isTrue);
    });
  });

  group('Subscription', () {
    Subscription sub({Map<String, Object?>? freeze, bool isCurrent = true}) =>
        Subscription.fromMap('s1', {
          'clientId': 'anna',
          'isCurrent': isCurrent,
          'startDate': '2026-09-01',
          'endDate': '2026-09-30',
          'trainingsTotal': 11,
          'trainingsLeft': 8,
          'freezeLimitDays': 3,
          'freeze': freeze,
        });

    CalendarDay d(String key) => CalendarDay.parse(key);

    test('«Осталось N дней» считает сегодняшний день', () {
      expect(sub().daysLeftOn(d('2026-09-17')), 14);
      expect(sub().daysLeftOn(d('2026-09-30')), 1);
      expect(sub().daysLeftOn(d('2026-10-01')), 0);
      // До начала — весь срок.
      expect(sub().daysLeftOn(d('2026-08-25')), 30);
    });

    test('активность по датам', () {
      expect(sub().isActiveOn(d('2026-09-01')), isTrue);
      expect(sub().isActiveOn(d('2026-09-30')), isTrue);
      expect(sub().isActiveOn(d('2026-10-01')), isFalse);
      expect(sub().isExpiredOn(d('2026-10-01')), isTrue);
      expect(sub(isCurrent: false).isActiveOn(d('2026-09-10')), isFalse);
    });

    test('заморозка: одна на период, границы включительно', () {
      expect(sub().canFreeze, isTrue);
      final frozen = sub(
        freeze: {'startDate': '2026-09-10', 'endDate': '2026-09-12', 'days': 3},
      );
      expect(frozen.canFreeze, isFalse);
      expect(frozen.isFrozenOn(d('2026-09-10')), isTrue);
      expect(frozen.isFrozenOn(d('2026-09-12')), isTrue);
      expect(frozen.isFrozenOn(d('2026-09-13')), isFalse);
    });

    test('без originalEndDate берётся endDate', () {
      expect(sub().originalEndDate, d('2026-09-30'));
    });

    test('без freezeLimitDays лимит тот же, что в settings/defaults', () {
      final s = Subscription.fromMap('s1', {
        'clientId': 'anna',
        'isCurrent': true,
        'startDate': '2026-09-01',
        'endDate': '2026-09-30',
        'trainingsTotal': 11,
        'trainingsLeft': 8,
      });
      expect(
        s.freezeLimitDays,
        AppSettings.fallback.subscription.freezeLimitDays,
      );
      expect(s.canFreeze, isTrue);
    });
  });

  test('FirestorePaths', () {
    expect(FirestorePaths.booking('t1', 'anna'), 'trainings/t1/bookings/anna');
    expect(FirestorePaths.settingsDefaults, 'settings/defaults');
  });
}
