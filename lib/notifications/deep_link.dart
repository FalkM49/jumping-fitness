import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Куда вести по тапу на уведомление (push или строка в истории).
sealed class DeepLink {
  const DeepLink();

  /// Разбор `data` уведомления (functions/src/notifications.ts).
  static DeepLink fromData(Map<String, String> data) {
    final kind = data['kind'];
    switch (kind) {
      case 'training_changed' ||
          'training_cancelled' ||
          'removed_from_training':
        final date = data['date'];
        final slot = data['slot'];
        if (date != null && slot != null) {
          try {
            return OpenTrainingCell(
              day: CalendarDay.parse(date),
              slot: DaySlot.fromWire(slot),
            );
          } on FormatException {
            return const OpenHome();
          }
        }
        return const OpenHome();
      case 'trainer_request_new':
        return const OpenTrainerRequests();
      case 'subscription_ending_soon' ||
          'subscription_low_trainings' ||
          'subscription_expired':
        return const OpenSubscription();
      default:
        return const OpenHome();
    }
  }
}

/// Главный экран своей роли.
final class OpenHome extends DeepLink {
  const OpenHome();
}

/// Абонемент на главном экране клиента.
final class OpenSubscription extends DeepLink {
  const OpenSubscription();
}

/// Окно ячейки календаря (тренировка, про которую уведомление).
@immutable
final class OpenTrainingCell extends DeepLink {
  const OpenTrainingCell({required this.day, required this.slot});

  final CalendarDay day;
  final DaySlot slot;

  @override
  bool operator ==(Object other) =>
      other is OpenTrainingCell && other.day == day && other.slot == slot;

  @override
  int get hashCode => Object.hash(day, slot);
}

/// «Заявки в тренеры» — для администратора.
final class OpenTrainerRequests extends DeepLink {
  const OpenTrainerRequests();
}
