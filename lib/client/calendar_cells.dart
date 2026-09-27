import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Режим общего календаря: сетка одна, различаются ячейки и окна (ТЗ 3.1, 3.2).
enum CalendarMode { client, trainer }

/// Что показано в ячейке «день + утро/вечер» (ТЗ 3, 3.1, 3.2).
sealed class CellView {
  const CellView();
}

/// Пусто — тренировки нет.
final class EmptyCell extends CellView {
  const EmptyCell();
}

/// Тренировка: доступная, с записью клиента или уже прошедшая.
final class TrainingCell extends CellView {
  const TrainingCell({
    required this.training,
    required this.booking,
    required this.isPast,
  });

  final Training training;

  /// Запись этого клиента на эту тренировку (любого статуса) или `null`.
  final Booking? booking;

  /// Тренировка уже началась — записываться и отменять поздно.
  final bool isPast;

  bool get isBooked => booking?.isActive ?? false;
}

/// «Отменено» — тренер отменил тренировку, на которую клиент был записан.
/// Видно только этому клиенту; остальные видят пустую ячейку (ТЗ 3.1).
final class CancelledCell extends CellView {
  const CancelledCell(this.training);

  final Training training;
}

/// Данные календаря для видимого отрезка дней.
@immutable
class CalendarData {
  CalendarData({
    required List<Training> trainings,
    required List<CalendarSlot> slots,
    required List<Booking> myBookings,
    required this.settings,
  }) : trainingsById = {
         for (final t in trainings)
           if (t.id != null) t.id!: t,
       },
       slotsByKey = {for (final s in slots) s.slotKey: s},
       bookingsByTraining = {for (final b in myBookings) b.trainingId: b};

  final Map<String, Training> trainingsById;
  final Map<String, CalendarSlot> slotsByKey;
  final Map<String, Booking> bookingsByTraining;
  final AppSettings settings;

  /// ID тренировки по расписанию после её создания сервером
  /// (functions/src/calendar.ts, `defaultTrainingId`).
  static String defaultTrainingId(String slotKey) => 'default_$slotKey';

  /// Какая тренировка стоит в ячейке — так же, как её определяет сервер
  /// (docs/02_firestore_schema.md, 2.4).
  Training? trainingAt(CalendarDay day, DaySlot slot) {
    final key = slotKeyOf(day, slot);
    final cell = slotsByKey[key];
    if (cell != null) {
      final id = cell.activeTrainingId;
      return id == null ? null : trainingsById[id];
    }
    if (!settings.training.weekdays.contains(day.weekday)) return null;
    return trainingsById[defaultTrainingId(key)] ??
        Training.virtualDefault(
          date: day,
          slot: slot,
          defaults: settings.training,
        );
  }

  /// Действующая (не отменённая) тренировка в ячейке.
  Training? activeTrainingAt(CalendarDay day, DaySlot slot) {
    final training = trainingAt(day, slot);
    return training == null || training.isCancelled ? null : training;
  }

  /// Ячейка в нужном режиме календаря.
  CellView cellFor(
    CalendarMode mode,
    CalendarDay day,
    DaySlot slot,
    DateTime now,
  ) => switch (mode) {
    CalendarMode.client => cellAt(day, slot, now),
    CalendarMode.trainer => trainerCellAt(day, slot, now),
  };

  /// Ячейка глазами тренера (ТЗ 3.2): отменённая тренировка выглядит как
  /// обычная пустая ячейка — в неё сразу можно назначить новую.
  CellView trainerCellAt(CalendarDay day, DaySlot slot, DateTime now) {
    final training = activeTrainingAt(day, slot);
    if (training == null) return const EmptyCell();
    return TrainingCell(
      training: training,
      booking: null,
      isPast: training.hasStartedAt(now),
    );
  }

  /// Ячейка глазами клиента (ТЗ 3.1).
  CellView cellAt(CalendarDay day, DaySlot slot, DateTime now) {
    final training = trainingAt(day, slot);
    if (training != null && !training.isCancelled) {
      return TrainingCell(
        training: training,
        booking: training.id == null ? null : bookingsByTraining[training.id],
        isPast: training.hasStartedAt(now),
      );
    }
    // В ячейке пусто: если клиент был записан на отменённую здесь
    // тренировку — показываем ему «Отменено».
    for (final booking in bookingsByTraining.values) {
      if (booking.status != BookingStatus.trainingCancelled) continue;
      final cancelled = trainingsById[booking.trainingId];
      if (cancelled != null &&
          cancelled.date == day &&
          cancelled.slot == slot) {
        return CancelledCell(cancelled);
      }
    }
    return const EmptyCell();
  }
}
