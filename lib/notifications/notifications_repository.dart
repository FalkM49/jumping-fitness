import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// История уведомлений пользователя (второй канал рядом с push, ТЗ 5).
abstract interface class NotificationsRepository {
  /// Последние уведомления, новые — сверху.
  Stream<List<AppNotification>> watch(String uid);

  /// Отметить прочитанными (правила разрешают менять только `read`).
  Future<void> markRead(String uid, Iterable<String> ids);
}

class FirestoreNotificationsRepository implements NotificationsRepository {
  FirestoreNotificationsRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  @override
  Stream<List<AppNotification>> watch(String uid) => _col(uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((q) {
        final result = <AppNotification>[];
        for (final doc in q.docs) {
          try {
            result.add(AppNotification.fromSnapshot(doc));
          } on FormatException catch (error) {
            debugPrint('Пропущено уведомление: ${error.message}');
          }
        }
        return result;
      });

  @override
  Future<void> markRead(String uid, Iterable<String> ids) async {
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_col(uid).doc(id), {'read': true});
    }
    await batch.commit();
  }
}

class UnavailableNotificationsRepository implements NotificationsRepository {
  const UnavailableNotificationsRepository();

  @override
  Stream<List<AppNotification>> watch(String uid) => Stream.value(const []);

  @override
  Future<void> markRead(String uid, Iterable<String> ids) async {}
}
