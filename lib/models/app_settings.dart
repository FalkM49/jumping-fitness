import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'day_slot.dart';
import 'firestore_parsing.dart';

/// Тренировка по умолчанию (ТЗ 3, 7).
@immutable
class TrainingDefaults {
  const TrainingDefaults({
    required this.weekdays,
    required this.morningTime,
    required this.eveningTime,
    required this.durationMinutes,
    required this.capacity,
  });

  /// ISO-дни недели с тренировками по умолчанию (1 = понедельник).
  final Set<int> weekdays;
  final TimeOfDayHm morningTime;
  final TimeOfDayHm eveningTime;
  final int durationMinutes;
  final int capacity;
}

/// Новый или продлеваемый абонемент (ТЗ 7).
@immutable
class SubscriptionDefaults {
  const SubscriptionDefaults({
    required this.durationDays,
    required this.trainings,
    required this.freezeLimitDays,
  });

  final int durationDays;
  final int trainings;
  final int freezeLimitDays;
}

/// Документ `settings/defaults`.
@immutable
class AppSettings {
  const AppSettings({
    required this.training,
    required this.subscription,
    required this.cancelWindowHours,
    required this.endingSoonDays,
    required this.lowTrainingsThreshold,
  });

  /// Значения из ТЗ — если документа в базе ещё нет или поле не заполнено.
  static const AppSettings fallback = AppSettings(
    training: TrainingDefaults(
      weekdays: {DateTime.monday, DateTime.wednesday, DateTime.friday},
      morningTime: TimeOfDayHm(8, 10),
      eveningTime: TimeOfDayHm(18, 0),
      durationMinutes: 60,
      capacity: 13,
    ),
    subscription: SubscriptionDefaults(
      durationDays: 30,
      trainings: 11,
      freezeLimitDays: 3,
    ),
    cancelWindowHours: 3,
    endingSoonDays: 5,
    lowTrainingsThreshold: 1,
  );

  factory AppSettings.fromMap(Map<String, Object?> data) {
    const f = fallback;
    final r = FirestoreReader('settings/defaults', data);
    final t = r.nested('training');
    final s = r.nested('subscription');
    final rules = r.nested('rules');

    // Время по умолчанию обязано попадать в свою строку сетки:
    // «утреннее» 15:00 нарисовалось бы не там.
    TimeOfDayHm time(
      FirestoreReader? reader,
      String key,
      DaySlot slot,
      TimeOfDayHm or,
    ) {
      TimeOfDayHm parse(String raw) {
        final value = TimeOfDayHm.parse(raw);
        if (slot.admits(value)) return value;
        throw FormatException(
          '${slot.label}: время должно быть '
          '${slot == DaySlot.morning ? 'раньше' : 'не раньше'} '
          '${DaySlot.eveningStartsAt}',
          raw,
        );
      }

      return reader?.optionalParsed(key, parse) ?? or;
    }

    int number(FirestoreReader? reader, String key, int min, int or) =>
        reader?.integerAtLeastOr(key, min, or) ?? or;

    final weekdays = t?.data['weekdays'];
    return AppSettings(
      training: TrainingDefaults(
        weekdays: weekdays is List<Object?>
            ? weekdays
                  .whereType<num>()
                  .map((d) => d.toInt())
                  .where((d) => d >= 1 && d <= 7)
                  .toSet()
            : f.training.weekdays,
        morningTime: time(
          t,
          'morningTime',
          DaySlot.morning,
          f.training.morningTime,
        ),
        eveningTime: time(
          t,
          'eveningTime',
          DaySlot.evening,
          f.training.eveningTime,
        ),
        durationMinutes: number(
          t,
          'durationMinutes',
          1,
          f.training.durationMinutes,
        ),
        capacity: number(t, 'capacity', 1, f.training.capacity),
      ),
      subscription: SubscriptionDefaults(
        durationDays: number(s, 'durationDays', 1, f.subscription.durationDays),
        trainings: number(s, 'trainings', 1, f.subscription.trainings),
        freezeLimitDays: number(
          s,
          'freezeLimitDays',
          0,
          f.subscription.freezeLimitDays,
        ),
      ),
      cancelWindowHours: number(
        rules,
        'cancelWindowHours',
        0,
        f.cancelWindowHours,
      ),
      endingSoonDays: number(rules, 'endingSoonDays', 0, f.endingSoonDays),
      lowTrainingsThreshold: number(
        rules,
        'lowTrainingsThreshold',
        0,
        f.lowTrainingsThreshold,
      ),
    );
  }

  factory AppSettings.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    return data == null ? fallback : AppSettings.fromMap(data);
  }

  final TrainingDefaults training;
  final SubscriptionDefaults subscription;

  /// Отмена записи доступна, только если до начала строго больше этого.
  final int cancelWindowHours;

  /// Порог «скоро закончится» по дням (подсветка + push).
  final int endingSoonDays;

  /// Порог push «мало тренировок».
  final int lowTrainingsThreshold;
}
