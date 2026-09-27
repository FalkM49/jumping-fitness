import 'package:flutter/foundation.dart';

/// Время студии. Москва живёт в UTC+3 круглый год (без перехода на летнее
/// время с 2014 года), поэтому хватает фиксированного смещения.
abstract final class StudioTime {
  static const String timezone = 'Europe/Moscow';
  static const Duration utcOffset = Duration(hours: 3);

  /// Момент [instant] как «настенные часы» студии (поля year…minute).
  static DateTime wallClock(DateTime instant) => instant.toUtc().add(utcOffset);
}

/// Календарный день студии без времени — то, что в Firestore хранится
/// строкой `YYYY-MM-DD`.
///
/// Не зависит от часового пояса телефона: день всегда считается по Москве.
@immutable
class CalendarDay implements Comparable<CalendarDay> {
  CalendarDay(int year, int month, int day)
    : this._(DateTime.utc(year, month, day));

  const CalendarDay._(this._utcMidnight);

  /// Разбирает строку `YYYY-MM-DD`. Невалидная дата — [FormatException].
  factory CalendarDay.parse(String key) {
    final match = _pattern.firstMatch(key);
    if (match == null) {
      throw FormatException('Ожидался день в формате YYYY-MM-DD', key);
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final result = CalendarDay(year, month, day);
    // DateTime молча «переносит» 31 февраля в март — такое не пропускаем.
    if (result.year != year || result.month != month || result.day != day) {
      throw FormatException('Несуществующая дата', key);
    }
    return result;
  }

  /// День студии, в который приходится момент [instant].
  factory CalendarDay.ofInstant(DateTime instant) {
    final wall = StudioTime.wallClock(instant);
    return CalendarDay(wall.year, wall.month, wall.day);
  }

  static final RegExp _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final DateTime _utcMidnight;

  int get year => _utcMidnight.year;
  int get month => _utcMidnight.month;
  int get day => _utcMidnight.day;

  /// ISO: 1 = понедельник … 7 = воскресенье.
  int get weekday => _utcMidnight.weekday;

  /// Ключ месяца `YYYY-MM` (цветок месяца).
  String get monthKey => '${_pad(year, 4)}-${_pad(month, 2)}';

  String toKey() => '${_pad(year, 4)}-${_pad(month, 2)}-${_pad(day, 2)}';

  CalendarDay addDays(int days) =>
      CalendarDay._(DateTime.utc(year, month, day + days));

  /// Сколько дней от [other] до этого дня (может быть отрицательным).
  int daysSince(CalendarDay other) =>
      _utcMidnight.difference(other._utcMidnight).inDays;

  bool isBefore(CalendarDay other) => compareTo(other) < 0;
  bool isAfter(CalendarDay other) => compareTo(other) > 0;

  /// Входит ли день в отрезок [from]…[to] включительно.
  bool isWithin(CalendarDay from, CalendarDay to) =>
      !isBefore(from) && !isAfter(to);

  /// Момент студии «этот день, [hour]:[minute]» как абсолютное время.
  DateTime atStudioTime(int hour, int minute) => DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
  ).subtract(StudioTime.utcOffset);

  @override
  int compareTo(CalendarDay other) =>
      _utcMidnight.compareTo(other._utcMidnight);

  @override
  bool operator ==(Object other) =>
      other is CalendarDay && other._utcMidnight == _utcMidnight;

  @override
  int get hashCode => _utcMidnight.hashCode;

  @override
  String toString() => toKey();

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');
}
