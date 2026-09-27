import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/client/booking_rules.dart';
import 'package:jumping_fitness/client/calendar_cells.dart';
import 'package:jumping_fitness/models/models.dart';
import 'package:jumping_fitness/utils/ru_format.dart';

import 'support/fake_studio.dart';

CalendarDay d(String key) => CalendarDay.parse(key);

Training training(
  String id,
  String day,
  DaySlot slot,
  TimeOfDayHm time, {
  int capacity = 13,
  int booked = 0,
  TrainingStatus status = TrainingStatus.scheduled,
}) => Training(
  id: id,
  date: d(day),
  slot: slot,
  startTime: time,
  startAt: d(day).atStudioTime(time.hour, time.minute),
  durationMinutes: 60,
  capacity: capacity,
  bookedCount: booked,
  status: status,
  source: TrainingSource.manual,
);

Booking booking(Training t, BookingStatus status) => Booking(
  clientId: 'me',
  clientName: 'Я',
  trainingId: t.id!,
  trainingStartAt: t.startAt,
  status: status,
  subscriptionId: 'sub',
);

CalendarSlot slotDoc(String day, DaySlot slot, String? activeId) =>
    CalendarSlot(
      slotKey: slotKeyOf(d(day), slot),
      date: d(day),
      slot: slot,
      activeTrainingId: activeId,
      overridesDefault: true,
    );

// Понедельник 28.09.2026, 12:00 по Москве.
final now = DateTime.utc(2026, 9, 28, 9);
const morning = TimeOfDayHm(8, 10);
const evening = TimeOfDayHm(18, 0);

void main() {
  group('ячейки календаря клиента', () {
    CalendarData data({
      List<Training> trainings = const [],
      List<CalendarSlot> slots = const [],
      List<Booking> bookings = const [],
    }) => CalendarData(
      trainings: trainings,
      slots: slots,
      myBookings: bookings,
      settings: AppSettings.fallback,
    );

    test(
      'пн/ср/пт без документов — тренировки по расписанию, остальные дни пусты',
      () {
        final cal = data();
        final mon =
            cal.cellAt(d('2026-09-28'), DaySlot.evening, now) as TrainingCell;
        expect(mon.training.isVirtual, isTrue);
        expect(mon.training.startTime, evening);
        expect(mon.isPast, isFalse);
        expect(
          cal.cellAt(d('2026-09-29'), DaySlot.evening, now),
          isA<EmptyCell>(),
        );
        // Утро сегодня уже началось.
        expect(
          (cal.cellAt(d('2026-09-28'), DaySlot.morning, now) as TrainingCell)
              .isPast,
          isTrue,
        );
      },
    );

    test('материализованная тренировка по расписанию берётся из базы', () {
      final t = training(
        'default_2026-09-30_morning',
        '2026-09-30',
        DaySlot.morning,
        morning,
        booked: 5,
      );
      final cell =
          data(trainings: [t]).cellAt(d('2026-09-30'), DaySlot.morning, now)
              as TrainingCell;
      expect(cell.training.bookedCount, 5);
    });

    test('ячейку переопределили: ручная тренировка или пусто', () {
      final t = training(
        'm1',
        '2026-09-29',
        DaySlot.morning,
        const TimeOfDayHm(9, 30),
      );
      final cal = data(
        trainings: [t],
        slots: [
          slotDoc('2026-09-29', DaySlot.morning, 'm1'),
          slotDoc('2026-09-30', DaySlot.evening, null),
        ],
        bookings: [booking(t, BookingStatus.active)],
      );
      final cell =
          cal.cellAt(d('2026-09-29'), DaySlot.morning, now) as TrainingCell;
      expect(cell.isBooked, isTrue);
      expect(
        cal.cellAt(d('2026-09-30'), DaySlot.evening, now),
        isA<EmptyCell>(),
      );
    });

    test('«Отменено» — только тому, кто был записан', () {
      final t = training(
        'c1',
        '2026-09-30',
        DaySlot.evening,
        evening,
        status: TrainingStatus.cancelled,
      );
      final slots = [slotDoc('2026-09-30', DaySlot.evening, null)];
      expect(
        data(
          trainings: [t],
          slots: slots,
          bookings: [booking(t, BookingStatus.trainingCancelled)],
        ).cellAt(d('2026-09-30'), DaySlot.evening, now),
        isA<CancelledCell>(),
      );
      expect(
        data(
          trainings: [t],
          slots: slots,
        ).cellAt(d('2026-09-30'), DaySlot.evening, now),
        isA<EmptyCell>(),
      );
    });

    test(
      'тренер поставил новую тренировку в слот отменённой — клиент видит новую',
      () {
        final old = training(
          'c1',
          '2026-09-30',
          DaySlot.evening,
          evening,
          status: TrainingStatus.cancelled,
        );
        final fresh = training(
          'n1',
          '2026-09-30',
          DaySlot.evening,
          const TimeOfDayHm(19, 0),
        );
        final cell = data(
          trainings: [old, fresh],
          slots: [slotDoc('2026-09-30', DaySlot.evening, 'n1')],
          bookings: [booking(old, BookingStatus.trainingCancelled)],
        ).cellAt(d('2026-09-30'), DaySlot.evening, now);
        expect((cell as TrainingCell).training.id, 'n1');
        expect(cell.isBooked, isFalse);
      },
    );
  });

  group('можно ли записаться (подсказка для значка (i))', () {
    final today = d('2026-09-28');
    final t = training('t1', '2026-09-29', DaySlot.evening, evening);
    final sub = subscription(
      clientId: 'me',
      start: d('2026-09-15'),
      end: d('2026-10-14'),
    );

    String? reason({Training? tr, Booking? b, Subscription? s}) =>
        bookingBlockReason(
          training: tr ?? t,
          booking: b,
          subscription: s,
          today: today,
          now: now,
        );

    test('всё в порядке — кнопка активна', () {
      expect(reason(s: sub), isNull);
    });

    test('конкретная причина в каждом случае', () {
      expect(reason(), contains('Нет действующего абонемента'));
      expect(
        reason(
          s: subscription(
            clientId: 'me',
            start: d('2026-08-01'),
            end: d('2026-09-27'),
          ),
        ),
        contains('Срок абонемента истёк'),
      );
      expect(
        reason(
          s: subscription(
            clientId: 'me',
            start: d('2026-10-01'),
            end: d('2026-10-30'),
          ),
        ),
        contains('начнёт действовать 1 октября'),
      );
      expect(
        reason(
          s: subscription(
            clientId: 'me',
            start: d('2026-09-01'),
            end: d('2026-09-28'),
          ),
        ),
        contains('действует по 28 сентября'),
      );
      expect(
        reason(
          s: subscription(
            clientId: 'me',
            start: d('2026-09-15'),
            end: d('2026-10-14'),
            freeze: SubscriptionFreeze(
              startDate: today,
              endDate: d('2026-09-30'),
              days: 3,
            ),
          ),
        ),
        contains('заморозка'),
      );
      expect(
        reason(
          s: subscription(
            clientId: 'me',
            start: d('2026-09-15'),
            end: d('2026-10-14'),
            left: 0,
          ),
        ),
        contains('не осталось тренировок'),
      );
      expect(
        reason(
          tr: training(
            'f',
            '2026-09-29',
            DaySlot.evening,
            evening,
            capacity: 5,
            booked: 5,
          ),
          s: sub,
        ),
        'Свободных мест нет.',
      );
      expect(
        reason(b: booking(t, BookingStatus.removedByTrainer), s: sub),
        contains('Тренер отменил'),
      );
      expect(
        reason(
          tr: training('p', '2026-09-28', DaySlot.morning, morning),
          s: sub,
        ),
        'Тренировка уже началась.',
      );
    });

    test('отмена: строго раньше чем за 3 часа', () {
      Training startsIn(Duration left) {
        final start = now.add(left);
        return Training(
          id: 'x',
          date: CalendarDay.ofInstant(start),
          slot: DaySlot.evening,
          startTime: const TimeOfDayHm(15, 0),
          startAt: start,
          durationMinutes: 60,
          capacity: 13,
          bookedCount: 1,
          status: TrainingStatus.scheduled,
          source: TrainingSource.manual,
        );
      }

      String? cancel(Duration left) => cancelBlockReason(
        training: startsIn(left),
        now: now,
        cancelWindowHours: 3,
      );

      expect(cancel(const Duration(hours: 3, minutes: 1)), isNull);
      expect(
        cancel(const Duration(hours: 3)),
        contains('Отмена уже недоступна'),
      );
      expect(cancel(const Duration(hours: 1)), isNotNull);
    });
  });

  group('русские формы', () {
    test('числа', () {
      expect(RuFormat.count(1, 'день', 'дня', 'дней'), '1 день');
      expect(RuFormat.count(3, 'день', 'дня', 'дней'), '3 дня');
      expect(RuFormat.count(11, 'день', 'дня', 'дней'), '11 дней');
      expect(RuFormat.count(21, 'день', 'дня', 'дней'), '21 день');
      expect(RuFormat.count(112, 'день', 'дня', 'дней'), '112 дней');
    });

    test('сроки и дни', () {
      expect(
        RuFormat.period(d('2026-09-01'), d('2026-09-30')),
        'с 1 по 30 сентября',
      );
      expect(
        RuFormat.period(d('2026-09-25'), d('2026-10-24')),
        'с 25 сентября по 24 октября',
      );
      expect(
        RuFormat.period(d('2026-12-20'), d('2027-01-18')),
        'с 20 декабря 2026 по 18 января 2027',
      );
      expect(RuFormat.weekdayShort(d('2026-09-28')), 'пн');
      expect(RuFormat.weekdayLong(d('2026-09-27')), 'Воскресенье');
      expect(RuFormat.monthName(9), 'Сентябрь');
    });
  });
}
