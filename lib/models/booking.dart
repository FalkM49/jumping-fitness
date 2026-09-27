import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'firestore_parsing.dart';

enum BookingStatus {
  /// Клиент записан: занимает место, тренировка списана.
  active('active'),

  /// Клиент отменил сам (раньше чем за 3 часа). Может записаться снова.
  cancelledByClient('cancelled_by_client'),

  /// Тренер удалил клиента из тренировки. Повторная запись запрещена.
  removedByTrainer('removed_by_trainer'),

  /// Тренер отменил всю тренировку. Клиент видит «Отменено».
  trainingCancelled('training_cancelled');

  const BookingStatus(this.wireName);

  final String wireName;

  static BookingStatus fromWire(String value) => values.firstWhere(
    (status) => status.wireName == value,
    orElse: () => throw FormatException('Неизвестный статус записи', value),
  );
}

/// Запись клиента `trainings/{trainingId}/bookings/{clientUid}`.
@immutable
class Booking {
  const Booking({
    required this.clientId,
    required this.clientName,
    required this.trainingId,
    required this.trainingStartAt,
    required this.status,
    required this.subscriptionId,
    this.bookedAt,
    this.cancelledAt,
  });

  factory Booking.fromMap(
    String trainingId,
    String clientId,
    Map<String, Object?> data,
  ) {
    final r = FirestoreReader('trainings/$trainingId/bookings/$clientId', data);
    return Booking(
      clientId: clientId,
      clientName: r.string('clientName'),
      trainingId: trainingId,
      trainingStartAt: r.timestamp('trainingStartAt'),
      status: r.parsed('status', BookingStatus.fromWire),
      subscriptionId: r.string('subscriptionId'),
      bookedAt: r.optionalTimestamp('bookedAt'),
      cancelledAt: r.optionalTimestamp('cancelledAt'),
    );
  }

  /// Из снимка — в том числе из запроса по группе коллекций `bookings`:
  /// ID тренировки берётся из пути родителя.
  factory Booking.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => Booking.fromMap(
    snapshot.reference.parent.parent!.id,
    snapshot.id,
    snapshot.data() ?? const {},
  );

  final String clientId;
  final String clientName;
  final String trainingId;
  final DateTime trainingStartAt;
  final BookingStatus status;

  /// Абонемент, с которого списана тренировка.
  final String subscriptionId;
  final DateTime? bookedAt;
  final DateTime? cancelledAt;

  bool get isActive => status == BookingStatus.active;

  /// Можно ли записаться на эту же тренировку снова.
  bool get allowsRebooking => status == BookingStatus.cancelledByClient;
}
