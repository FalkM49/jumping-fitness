import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'calendar_day.dart';
import 'firestore_parsing.dart';

/// Использованная заморозка абонемента.
@immutable
class SubscriptionFreeze {
  const SubscriptionFreeze({
    required this.startDate,
    required this.endDate,
    required this.days,
  });

  final CalendarDay startDate;

  /// Последний день заморозки включительно.
  final CalendarDay endDate;
  final int days;

  bool covers(CalendarDay day) => day.isWithin(startDate, endDate);
}

/// Абонемент `subscriptions/{id}` — один документ на период (ТЗ 5, 6).
///
/// Хранятся только факты; «активен», «заморожен», «осталось дней»
/// вычисляются здесь от переданного дня. Окончательное решение
/// «можно ли записаться» всегда принимает Cloud Function по серверному
/// времени — эти методы нужны для отображения.
@immutable
class Subscription {
  const Subscription({
    required this.id,
    required this.clientId,
    required this.isCurrent,
    required this.startDate,
    required this.endDate,
    required this.originalEndDate,
    required this.trainingsTotal,
    required this.trainingsLeft,
    required this.freezeLimitDays,
    this.freeze,
    this.expiredAt,
    this.burnedTrainings = 0,
    this.createdAt,
    this.closedAt,
  });

  factory Subscription.fromMap(String id, Map<String, Object?> data) {
    final r = FirestoreReader('subscriptions/$id', data);
    final f = r.nested('freeze');
    final endDate = r.day('endDate');
    return Subscription(
      id: id,
      clientId: r.string('clientId'),
      isCurrent: r.boolean('isCurrent'),
      startDate: r.day('startDate'),
      endDate: endDate,
      originalEndDate: r.optionalDay('originalEndDate') ?? endDate,
      trainingsTotal: r.integerAtLeast('trainingsTotal', 0),
      trainingsLeft: r.integerAtLeast('trainingsLeft', 0),
      // Тот же запасной лимит, что в settings/defaults (ТЗ 7: 3 дня).
      freezeLimitDays: r.integerAtLeastOr(
        'freezeLimitDays',
        0,
        AppSettings.fallback.subscription.freezeLimitDays,
      ),
      freeze: f == null
          ? null
          : SubscriptionFreeze(
              startDate: f.day('startDate'),
              endDate: f.day('endDate'),
              days: f.integer('days'),
            ),
      expiredAt: r.optionalTimestamp('expiredAt'),
      burnedTrainings: r.integerOr('burnedTrainings', 0),
      createdAt: r.optionalTimestamp('createdAt'),
      closedAt: r.optionalTimestamp('closedAt'),
    );
  }

  factory Subscription.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => Subscription.fromMap(snapshot.id, snapshot.data() ?? const {});

  final String id;
  final String clientId;
  final bool isCurrent;
  final CalendarDay startDate;

  /// «по …» включительно, с учётом сдвига заморозкой.
  final CalendarDay endDate;
  final CalendarDay originalEndDate;
  final int trainingsTotal;
  final int trainingsLeft;
  final int freezeLimitDays;
  final SubscriptionFreeze? freeze;
  final DateTime? expiredAt;
  final int burnedTrainings;
  final DateTime? createdAt;
  final DateTime? closedAt;

  /// Действует ли абонемент по датам в день [today].
  bool isActiveOn(CalendarDay today) =>
      isCurrent && today.isWithin(startDate, endDate);

  /// Идёт ли заморозка в день [today].
  bool isFrozenOn(CalendarDay today) => freeze?.covers(today) ?? false;

  /// Срок вышел (последний день уже прошёл).
  bool isExpiredOn(CalendarDay today) => today.isAfter(endDate);

  /// Сколько дней осталось, включая сегодняшний. 0 — срок вышел.
  int daysLeftOn(CalendarDay today) {
    final from = today.isBefore(startDate) ? startDate : today;
    final days = endDate.daysSince(from) + 1;
    return days < 0 ? 0 : days;
  }

  /// Заморозка ещё не использована в этом периоде (ТЗ 5).
  bool get canFreeze => isCurrent && freeze == null && freezeLimitDays > 0;

  bool get hasTrainingsLeft => trainingsLeft > 0;
}
