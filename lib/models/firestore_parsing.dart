import 'package:cloud_firestore/cloud_firestore.dart';

import 'calendar_day.dart';

/// Строгое чтение полей документа.
///
/// Обязательное поле отсутствует или другого типа → [FormatException]
/// с путём документа: битые данные должны быть видны сразу, а не
/// превращаться в «0 тренировок» на экране.
class FirestoreReader {
  FirestoreReader(this.path, this.data);

  final String path;
  final Map<String, Object?> data;

  T _require<T>(String key) {
    final value = data[key];
    if (value is T) return value;
    throw FormatException(
      '$path: поле «$key» должно быть ${_typeName<T>()}, а не '
      '${value == null ? 'пустым' : value.runtimeType}',
    );
  }

  T? _optional<T>(String key) {
    final value = data[key];
    if (value == null || value is T) return value as T?;
    throw FormatException(
      '$path: поле «$key» должно быть ${_typeName<T>()}, а не '
      '${value.runtimeType}',
    );
  }

  String string(String key) => _require<String>(key);
  String? optionalString(String key) => _optional<String>(key);

  bool boolean(String key) => _require<bool>(key);
  bool booleanOr(String key, bool fallback) => _optional<bool>(key) ?? fallback;

  int integer(String key) => _toInt(key, _require<num>(key));
  int integerOr(String key, int fallback) {
    final value = _optional<num>(key);
    return value == null ? fallback : _toInt(key, value);
  }

  /// Целое не меньше [min]: отрицательные места или длительность —
  /// битые данные, а не повод падать позже в вычислениях.
  int integerAtLeast(String key, int min) => _checkMin(key, integer(key), min);
  int integerAtLeastOr(String key, int min, int fallback) =>
      _checkMin(key, integerOr(key, fallback), min);

  /// Дробное число молча не обрезаем: 13.7 места — это ошибка в данных.
  /// 13.0 допустимо (так число может сохранить Console или JS).
  int _toInt(String key, num value) {
    if (value is int) return value;
    if (value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    throw FormatException(
      '$path: поле «$key» должно быть целым числом, а не $value',
    );
  }

  int _checkMin(String key, int value, int min) {
    if (value >= min) return value;
    throw FormatException(
      '$path: поле «$key» должно быть не меньше $min, а не $value',
    );
  }

  /// Момент времени всегда в UTC: `Timestamp.toDate()` отдаёт время в поясе
  /// телефона, а смешение UTC/локальных DateTime ломает сравнения на `==`.
  /// Для показа пользователю время переводится в пояс студии (StudioTime).
  DateTime timestamp(String key) => _require<Timestamp>(key).toDate().toUtc();
  DateTime? optionalTimestamp(String key) =>
      _optional<Timestamp>(key)?.toDate().toUtc();

  CalendarDay day(String key) {
    final raw = string(key);
    return _wrap(key, () => CalendarDay.parse(raw));
  }

  CalendarDay? optionalDay(String key) {
    final raw = optionalString(key);
    return raw == null ? null : _wrap(key, () => CalendarDay.parse(raw));
  }

  List<String> stringList(String key) {
    final raw = _optional<List<Object?>>(key) ?? const [];
    return List<String>.unmodifiable(raw.whereType<String>());
  }

  Map<String, Object?>? optionalMap(String key) {
    final raw = _optional<Map<Object?, Object?>>(key);
    return raw?.map((k, v) => MapEntry(k.toString(), v));
  }

  /// Вложенная карта как отдельный читатель (например, `freeze`).
  FirestoreReader? nested(String key) {
    final map = optionalMap(key);
    return map == null ? null : FirestoreReader('$path.$key', map);
  }

  /// Строка, разобранная через [parse] (перечисление, время…);
  /// ошибки разбора получают путь документа.
  E parsed<E>(String key, E Function(String) parse) {
    final raw = string(key);
    return _wrap(key, () => parse(raw));
  }

  /// Как [parsed], но поля может не быть: тогда `null`.
  E? optionalParsed<E>(String key, E Function(String) parse) {
    final raw = optionalString(key);
    return raw == null ? null : _wrap(key, () => parse(raw));
  }

  T _wrap<T>(String key, T Function() compute) {
    try {
      return compute();
    } on FormatException catch (error) {
      throw FormatException('$path: поле «$key»: ${error.message}');
    }
  }

  static String _typeName<T>() => switch (T) {
    const (String) => 'строкой',
    const (bool) => 'логическим',
    const (num) => 'числом',
    const (Timestamp) => 'датой-временем',
    _ => T.toString(),
  };
}
