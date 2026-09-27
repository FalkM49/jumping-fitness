import 'dart:async';

import 'package:jumping_fitness/models/models.dart';
import 'package:jumping_fitness/notifications/notifications_repository.dart';
import 'package:jumping_fitness/notifications/push_service.dart';

/// Push в памяти: тест сам «присылает» сообщения.
class FakePush implements PushService {
  final _foreground = StreamController<PushMessage>.broadcast();
  final _opened = StreamController<PushMessage>.broadcast();

  final List<String> started = [];
  final List<String> stopped = [];

  @override
  Future<void> start(String uid) async => started.add(uid);

  @override
  Future<void> stop(String uid) async => stopped.add(uid);

  @override
  Stream<PushMessage> get foreground => _foreground.stream;

  @override
  Stream<PushMessage> get opened => _opened.stream;

  PushPermission permissionStatus = PushPermission.granted;
  final List<String> enabled = [];

  @override
  Future<PushPermission> permission() async => permissionStatus;

  @override
  Future<bool> enable(String uid) async {
    enabled.add(uid);
    permissionStatus = PushPermission.granted;
    return true;
  }

  void arriveWhileOpen(PushMessage message) => _foreground.add(message);

  void tapInSystemTray(PushMessage message) => _opened.add(message);
}

/// История уведомлений в памяти.
class FakeNotifications implements NotificationsRepository {
  final List<AppNotification> items = [];
  final List<String> markedRead = [];
  final _changed = StreamController<void>.broadcast();

  void put(AppNotification n) {
    items.insert(0, n);
    _changed.add(null);
  }

  @override
  Stream<List<AppNotification>> watch(String uid) async* {
    yield List.of(items);
    yield* _changed.stream.map((_) => List.of(items));
  }

  @override
  Future<void> markRead(String uid, Iterable<String> ids) async {
    markedRead.addAll(ids);
    for (var i = 0; i < items.length; i++) {
      final n = items[i];
      if (ids.contains(n.id)) {
        items[i] = AppNotification(
          id: n.id,
          kind: n.kind,
          title: n.title,
          body: n.body,
          data: n.data,
          read: true,
          createdAt: n.createdAt,
        );
      }
    }
    _changed.add(null);
  }
}

AppNotification notification(
  String id, {
  String kind = 'training_changed',
  String title = 'Тренировка изменена',
  String body = 'Тренировка теперь в 19:00.',
  Map<String, String> data = const {},
  bool read = false,
}) => AppNotification(
  id: id,
  kind: kind,
  title: title,
  body: body,
  data: {'kind': kind, ...data},
  read: read,
  createdAt: DateTime.utc(2026, 9, 28, 8),
);
