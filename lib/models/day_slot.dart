import 'package:flutter/foundation.dart';

import 'calendar_day.dart';

/// Время суток `HH:mm`.
@immutable
class TimeOfDayHm implements Comparable<TimeOfDayHm> {
  const TimeOfDayHm(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  factory TimeOfDayHm.parse(String value) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value);
    if (match == null) {
      throw FormatException('Ожидалось время в формате HH:mm', value);
    }
    return TimeOfDayHm(int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  final int hour;
  final int minute;

  int get minutesOfDay => hour * 60 + minute;

  String format() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(TimeOfDayHm other) => minutesOfDay - other.minutesOfDay;

  @override
  bool operator ==(Object other) =>
      other is TimeOfDayHm && other.minutesOfDay == minutesOfDay;

  @override
  int get hashCode => minutesOfDay;

  @override
  String toString() => format();
}

/// Строка календарной сетки: «Утро» или «Вечер» (ТЗ 3).
enum DaySlot {
  morning('morning', 'Утро'),
  evening('evening', 'Вечер');

  const DaySlot(this.wireName, this.label);

  /// Значение в Firestore.
  final String wireName;

  /// Подпись в интерфейсе.
  final String label;

  /// Граница строк: утренняя тренировка начинается до 14:00,
  /// вечерняя — с 14:00 (docs/02_firestore_schema.md, раздел 3).
  static const TimeOfDayHm eveningStartsAt = TimeOfDayHm(14, 0);

  /// Строка сетки, в которую попадает тренировка с началом в [time].
  static DaySlot ofTime(TimeOfDayHm time) =>
      time.compareTo(eveningStartsAt) < 0 ? morning : evening;

  /// Может ли тренировка этой строки начинаться в [time].
  bool admits(TimeOfDayHm time) => ofTime(time) == this;

  static DaySlot fromWire(String value) => values.firstWhere(
    (slot) => slot.wireName == value,
    orElse: () => throw FormatException('Неизвестный слот', value),
  );
}

/// Ключ ячейки календаря: `YYYY-MM-DD_morning` / `YYYY-MM-DD_evening`.
/// Это ID документа в `calendar_slots`.
String slotKeyOf(CalendarDay day, DaySlot slot) =>
    '${day.toKey()}_${slot.wireName}';
