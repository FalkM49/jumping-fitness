import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'calendar_day.dart';
import 'day_slot.dart';
import 'firestore_parsing.dart';

enum TrainingStatus {
  scheduled('scheduled'),
  cancelled('cancelled');

  const TrainingStatus(this.wireName);

  final String wireName;

  static TrainingStatus fromWire(String value) => values.firstWhere(
    (status) => status.wireName == value,
    orElse: () => throw FormatException('Неизвестный статус тренировки', value),
  );
}

enum TrainingSource {
  /// Из расписания по умолчанию (пн/ср/пт).
  defaultSchedule('default'),

  /// Назначена тренером вручную.
  manual('manual');

  const TrainingSource(this.wireName);

  final String wireName;

  static TrainingSource fromWire(String value) => values.firstWhere(
    (source) => source.wireName == value,
    orElse: () => throw FormatException('Неизвестный источник', value),
  );
}

/// Тренировка `trainings/{id}`.
///
/// [id] == `null` — «виртуальная» тренировка по расписанию по умолчанию,
/// которой ещё нет в базе: её показывают в календаре, а документ создаёт
/// функция при первой записи или правке тренером.
@immutable
class Training {
  const Training({
    required this.id,
    required this.date,
    required this.slot,
    required this.startTime,
    required this.startAt,
    required this.durationMinutes,
    required this.capacity,
    required this.bookedCount,
    required this.status,
    required this.source,
    this.updatedBy,
    this.updatedAt,
  });

  factory Training.fromMap(String id, Map<String, Object?> data) {
    final r = FirestoreReader('trainings/$id', data);
    return Training(
      id: id,
      date: r.day('date'),
      slot: r.parsed('slot', DaySlot.fromWire),
      startTime: r.parsed('startTime', TimeOfDayHm.parse),
      startAt: r.timestamp('startAt'),
      durationMinutes: r.integerAtLeast('durationMinutes', 1),
      capacity: r.integerAtLeast('capacity', 0),
      bookedCount: r.integerAtLeast('bookedCount', 0),
      status: r.parsed('status', TrainingStatus.fromWire),
      source: r.parsed('source', TrainingSource.fromWire),
      updatedBy: r.optionalString('updatedBy'),
      updatedAt: r.optionalTimestamp('updatedAt'),
    );
  }

  factory Training.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => Training.fromMap(snapshot.id, snapshot.data() ?? const {});

  /// Виртуальная тренировка по умолчанию для ячейки [date]/[slot].
  factory Training.virtualDefault({
    required CalendarDay date,
    required DaySlot slot,
    required TrainingDefaults defaults,
  }) {
    final time = switch (slot) {
      DaySlot.morning => defaults.morningTime,
      DaySlot.evening => defaults.eveningTime,
    };
    return Training(
      id: null,
      date: date,
      slot: slot,
      startTime: time,
      startAt: date.atStudioTime(time.hour, time.minute),
      durationMinutes: defaults.durationMinutes,
      capacity: defaults.capacity,
      bookedCount: 0,
      status: TrainingStatus.scheduled,
      source: TrainingSource.defaultSchedule,
    );
  }

  final String? id;
  final CalendarDay date;
  final DaySlot slot;
  final TimeOfDayHm startTime;

  /// Абсолютный момент начала — по нему считается правило 3 часов.
  final DateTime startAt;
  final int durationMinutes;
  final int capacity;
  final int bookedCount;
  final TrainingStatus status;
  final TrainingSource source;
  final String? updatedBy;
  final DateTime? updatedAt;

  String get slotKey => slotKeyOf(date, slot);
  bool get isVirtual => id == null;
  bool get isCancelled => status == TrainingStatus.cancelled;
  DateTime get endAt => startAt.add(Duration(minutes: durationMinutes));
  int get freePlaces => bookedCount >= capacity ? 0 : capacity - bookedCount;
  bool get isFull => freePlaces == 0;

  /// Тренировка уже началась к моменту [now].
  bool hasStartedAt(DateTime now) => !now.isBefore(startAt);
}
