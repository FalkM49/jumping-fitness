import '../models/models.dart';
import '../utils/ru_format.dart';

/// Почему кнопка «Записаться» неактивна — текст для значка (i) (ТЗ 3.1).
///
/// Это только подсказка интерфейса: окончательно всё проверяет Cloud
/// Function по серверному времени, и если она откажет, покажем её текст.
/// Порядок проверок — тот же, что на сервере (functions/src/bookings.ts).
String? bookingBlockReason({
  required Training training,
  required Booking? booking,
  required Subscription? subscription,
  required CalendarDay today,
  required DateTime now,
}) {
  if (training.isCancelled) return 'Тренировка отменена.';
  if (training.hasStartedAt(now)) return 'Тренировка уже началась.';
  if (booking?.status == BookingStatus.removedByTrainer) {
    return 'Тренер отменил вашу запись на эту тренировку — записаться на неё снова нельзя.';
  }

  final sub = subscription;
  if (sub == null || !sub.isCurrent) {
    return 'Нет действующего абонемента. Оформите его у тренера.';
  }
  if (today.isBefore(sub.startDate)) {
    return 'Абонемент начнёт действовать ${RuFormat.dayMonth(sub.startDate)}.';
  }
  if (sub.isExpiredOn(today)) {
    return 'Срок абонемента истёк. Продлите его у тренера.';
  }
  if (!training.date.isWithin(sub.startDate, sub.endDate)) {
    return 'Абонемент действует по ${RuFormat.dayMonth(sub.endDate)} — '
        'на более позднюю тренировку записаться нельзя.';
  }
  final freeze = sub.freeze;
  if (freeze != null && freeze.covers(today)) {
    return 'Идёт заморозка абонемента до ${RuFormat.dayMonth(freeze.endDate)} включительно.';
  }
  if (!sub.hasTrainingsLeft) {
    return 'На абонементе не осталось тренировок. Продлите его у тренера.';
  }
  if (training.isFull) return 'Свободных мест нет.';
  return null;
}

/// Почему «Отменить запись» неактивна: отмена доступна строго раньше чем
/// за [cancelWindowHours] до начала (ТЗ 3.1).
String? cancelBlockReason({
  required Training training,
  required DateTime now,
  required int cancelWindowHours,
}) {
  final left = training.startAt.difference(now);
  if (left > Duration(hours: cancelWindowHours)) return null;
  return 'Отмена уже недоступна: отменить запись можно не позже чем за '
      '$cancelWindowHours ч до начала тренировки.';
}
