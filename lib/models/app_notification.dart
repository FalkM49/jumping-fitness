import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'firestore_parsing.dart';

/// Уведомление из истории `users/{uid}/notifications/{id}` (этап 7).
/// Та же запись, что пришла push-сообщением, — чтобы пропущенный push
/// можно было посмотреть в приложении.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.data,
    required this.read,
    this.createdAt,
  });

  factory AppNotification.fromMap(String id, Map<String, Object?> data) {
    final r = FirestoreReader('notifications/$id', data);
    final extra = r.optionalMap('data') ?? const {};
    return AppNotification(
      id: id,
      kind: r.string('kind'),
      title: r.string('title'),
      body: r.string('body'),
      data: {
        for (final e in extra.entries)
          if (e.value is String) e.key: e.value! as String,
      },
      read: r.booleanOr('read', false),
      createdAt: r.optionalTimestamp('createdAt'),
    );
  }

  factory AppNotification.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => AppNotification.fromMap(snapshot.id, snapshot.data() ?? const {});

  final String id;

  /// Вид события: `training_changed`, `subscription_expired`…
  /// (functions/src/notifications.ts).
  final String kind;
  final String title;
  final String body;

  /// Данные для перехода: trainingId, date, slot…
  final Map<String, String> data;
  final bool read;
  final DateTime? createdAt;
}
