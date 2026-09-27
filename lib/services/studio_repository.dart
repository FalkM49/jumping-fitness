import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Данные студии для экранов: календарь, записи, абонемент, цветок,
/// значения по умолчанию. Только чтение — всё, что меняет данные, идёт
/// через Cloud Functions ([StudioFunctions]).
abstract interface class StudioRepository {
  Stream<AppSettings> watchSettings();

  /// Тренировки с датой в отрезке [from]…[to] (включая отменённые).
  Stream<List<Training>> watchTrainings(CalendarDay from, CalendarDay to);

  /// Ячейки календаря в отрезке [from]…[to].
  Stream<List<CalendarSlot>> watchSlots(CalendarDay from, CalendarDay to);

  /// Записи клиента [uid] на тренировки, начинающиеся не раньше [from].
  Stream<List<Booking>> watchMyBookings(String uid, DateTime from);

  Stream<Subscription?> watchSubscription(String subscriptionId);

  Stream<Flower?> watchFlower(String flowerId);

  // ------------------------------------------------ только тренер/админ

  /// Активные записи на тренировку — список записавшихся (ТЗ 3.2).
  Stream<List<Booking>> watchTrainingBookings(String trainingId);

  /// Все клиенты студии (роль client) — список клиентов (ТЗ 6).
  Stream<List<UserProfile>> watchClients();

  /// Текущие абонементы всех клиентов.
  Stream<List<Subscription>> watchCurrentSubscriptions();
}

class FirestoreStudioRepository implements StudioRepository {
  FirestoreStudioRepository(this._db);

  final FirebaseFirestore _db;

  /// Битый документ не должен ронять весь календарь: пропускаем его
  /// и пишем в лог.
  static List<T> _parseAll<T>(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> docs,
    T Function(DocumentSnapshot<Map<String, dynamic>>) parse,
  ) {
    final result = <T>[];
    for (final doc in docs) {
      try {
        result.add(parse(doc));
      } on FormatException catch (error) {
        debugPrint('Пропущен документ: ${error.message}');
      }
    }
    return result;
  }

  @override
  Stream<AppSettings> watchSettings() => _db
      .doc(FirestorePaths.settingsDefaults)
      .snapshots()
      .map(AppSettings.fromSnapshot);

  @override
  Stream<List<Training>> watchTrainings(CalendarDay from, CalendarDay to) => _db
      .collection(FirestorePaths.trainings)
      .where('date', isGreaterThanOrEqualTo: from.toKey())
      .where('date', isLessThanOrEqualTo: to.toKey())
      .snapshots()
      .map((q) => _parseAll(q.docs, Training.fromSnapshot));

  @override
  Stream<List<CalendarSlot>> watchSlots(CalendarDay from, CalendarDay to) => _db
      .collection(FirestorePaths.calendarSlots)
      .where('date', isGreaterThanOrEqualTo: from.toKey())
      .where('date', isLessThanOrEqualTo: to.toKey())
      .snapshots()
      .map((q) => _parseAll(q.docs, CalendarSlot.fromSnapshot));

  @override
  Stream<List<Booking>> watchMyBookings(String uid, DateTime from) => _db
      // Правила пускают к группе bookings только с фильтром по своему uid.
      .collectionGroup(FirestorePaths.bookings)
      .where('clientId', isEqualTo: uid)
      .where(
        'trainingStartAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(from),
      )
      .snapshots()
      .map((q) => _parseAll(q.docs, Booking.fromSnapshot));

  @override
  Stream<Subscription?> watchSubscription(String subscriptionId) => _db
      .doc(FirestorePaths.subscription(subscriptionId))
      .snapshots()
      .map((s) => s.exists ? Subscription.fromSnapshot(s) : null);

  @override
  Stream<Flower?> watchFlower(String flowerId) => _db
      .doc(FirestorePaths.flower(flowerId))
      .snapshots()
      .map((s) => s.exists ? Flower.fromSnapshot(s) : null);

  @override
  Stream<List<Booking>> watchTrainingBookings(String trainingId) => _db
      .doc(FirestorePaths.training(trainingId))
      .collection(FirestorePaths.bookings)
      .where('status', isEqualTo: BookingStatus.active.wireName)
      .snapshots()
      .map((q) => _parseAll(q.docs, Booking.fromSnapshot));

  @override
  Stream<List<UserProfile>> watchClients() => _db
      .collection(FirestorePaths.users)
      .where('role', isEqualTo: UserRole.client.wireName)
      .snapshots()
      .map((q) => _parseAll(q.docs, UserProfile.fromSnapshot));

  @override
  Stream<List<Subscription>> watchCurrentSubscriptions() => _db
      .collection(FirestorePaths.subscriptions)
      .where('isCurrent', isEqualTo: true)
      .snapshots()
      .map((q) => _parseAll(q.docs, Subscription.fromSnapshot));
}

/// Firebase ещё не подключён: данных нет.
class UnavailableStudioRepository implements StudioRepository {
  const UnavailableStudioRepository();

  @override
  Stream<AppSettings> watchSettings() => Stream.value(AppSettings.fallback);

  @override
  Stream<List<Training>> watchTrainings(CalendarDay from, CalendarDay to) =>
      Stream.value(const []);

  @override
  Stream<List<CalendarSlot>> watchSlots(CalendarDay from, CalendarDay to) =>
      Stream.value(const []);

  @override
  Stream<List<Booking>> watchMyBookings(String uid, DateTime from) =>
      Stream.value(const []);

  @override
  Stream<Subscription?> watchSubscription(String subscriptionId) =>
      Stream.value(null);

  @override
  Stream<Flower?> watchFlower(String flowerId) => Stream.value(null);

  @override
  Stream<List<Booking>> watchTrainingBookings(String trainingId) =>
      Stream.value(const []);

  @override
  Stream<List<UserProfile>> watchClients() => Stream.value(const []);

  @override
  Stream<List<Subscription>> watchCurrentSubscriptions() =>
      Stream.value(const []);
}
