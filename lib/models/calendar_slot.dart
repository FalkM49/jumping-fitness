import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'calendar_day.dart';
import 'day_slot.dart';
import 'firestore_parsing.dart';

/// `calendar_slots/{slotKey}` — что стоит в ячейке «день + утро/вечер».
///
/// Документа нет → в ячейке тренировка по расписанию по умолчанию
/// (если день входит в `settings.training.weekdays`) или пусто.
@immutable
class CalendarSlot {
  const CalendarSlot({
    required this.slotKey,
    required this.date,
    required this.slot,
    required this.activeTrainingId,
    required this.overridesDefault,
  });

  factory CalendarSlot.fromMap(String slotKey, Map<String, Object?> data) {
    final r = FirestoreReader('calendar_slots/$slotKey', data);
    return CalendarSlot(
      slotKey: slotKey,
      date: r.day('date'),
      slot: r.parsed('slot', DaySlot.fromWire),
      activeTrainingId: r.optionalString('activeTrainingId'),
      overridesDefault: r.booleanOr('overridesDefault', false),
    );
  }

  factory CalendarSlot.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => CalendarSlot.fromMap(snapshot.id, snapshot.data() ?? const {});

  final String slotKey;
  final CalendarDay date;
  final DaySlot slot;

  /// Активная тренировка в ячейке или `null`, если пусто.
  final String? activeTrainingId;

  /// Ячейку меняли вручную — тренировку по умолчанию здесь не рисовать.
  final bool overridesDefault;
}
