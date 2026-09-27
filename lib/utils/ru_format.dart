import '../models/calendar_day.dart';

/// Даты и числа по-русски во времени студии (Москва), без зависимости
/// от локали телефона и от инициализации `intl`.
abstract final class RuFormat {
  static const List<String> _monthsGenitive = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  static const List<String> _monthsNominative = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  static const List<String> _weekdaysShort = [
    'пн',
    'вт',
    'ср',
    'чт',
    'пт',
    'сб',
    'вс',
  ];

  static const List<String> _weekdaysLong = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  /// `26 сентября 2026`
  static String date(DateTime instant) {
    final wall = StudioTime.wallClock(instant);
    return '${wall.day} ${_monthsGenitive[wall.month - 1]} ${wall.year}';
  }

  /// `26 сентября 2026, 14:05`
  static String dateTime(DateTime instant) {
    final wall = StudioTime.wallClock(instant);
    final hh = wall.hour.toString().padLeft(2, '0');
    final mm = wall.minute.toString().padLeft(2, '0');
    return '${date(instant)}, $hh:$mm';
  }

  /// Обратный отсчёт `0:45` / `1:00`.
  static String countdown(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// `Сентябрь` — подпись месяца над группой дней в календаре.
  static String monthName(int month) => _monthsNominative[month - 1];

  /// `пн` … `вс`.
  static String weekdayShort(CalendarDay day) =>
      _weekdaysShort[day.weekday - 1];

  /// `Пятница`.
  static String weekdayLong(CalendarDay day) => _weekdaysLong[day.weekday - 1];

  /// `26 сентября`
  static String dayMonth(CalendarDay day) =>
      '${day.day} ${_monthsGenitive[day.month - 1]}';

  /// `с 1 по 30 сентября` / `с 25 сентября по 24 октября` / с годом, если
  /// годы разные.
  static String period(CalendarDay from, CalendarDay to) {
    if (from.year != to.year) {
      return 'с ${dayMonth(from)} ${from.year} по ${dayMonth(to)} ${to.year}';
    }
    if (from.month == to.month) {
      return 'с ${from.day} по ${dayMonth(to)}';
    }
    return 'с ${dayMonth(from)} по ${dayMonth(to)}';
  }

  /// Выбор формы слова по числу: `plural(5, 'день', 'дня', 'дней')` → `дней`.
  static String plural(int n, String one, String few, String many) {
    final mod100 = n.abs() % 100;
    final mod10 = n.abs() % 10;
    if (mod100 >= 11 && mod100 <= 14) return many;
    if (mod10 == 1) return one;
    if (mod10 >= 2 && mod10 <= 4) return few;
    return many;
  }

  /// `14 дней`, `1 тренировка`.
  static String count(int n, String one, String few, String many) =>
      '$n ${plural(n, one, few, many)}';
}
