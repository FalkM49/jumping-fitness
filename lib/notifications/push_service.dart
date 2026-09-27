import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Push-сообщение, как его видит приложение.
@immutable
class PushMessage {
  const PushMessage({
    required this.title,
    required this.body,
    required this.data,
  });

  final String title;
  final String body;
  final Map<String, String> data;
}

/// Push-уведомления через Firebase Cloud Messaging (ТЗ 2, 3.2, 5).
///
/// - [start] — после входа: разрешение на уведомления, токен устройства
///   в users/{uid}/devices/{deviceId}, обновление токена при его смене.
/// - [stop] — перед выходом: токен удаляется, чтобы на телефон больше не
///   приходили уведомления прошлого аккаунта.
/// - [foreground] — сообщения, пришедшие, пока приложение открыто
///   (показываются баннером внутри приложения).
/// - [opened] — тап по системному уведомлению, когда приложение было
///   в фоне или закрыто (переход к нужному экрану).
abstract interface class PushService {
  Future<void> start(String uid);

  Future<void> stop(String uid);

  Stream<PushMessage> get foreground;

  Stream<PushMessage> get opened;
}

class FirebasePushService implements PushService {
  FirebasePushService(this._messaging, this._db);

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _db;

  static const _deviceIdKey = 'push.deviceId';

  final _foreground = StreamController<PushMessage>.broadcast();
  final _opened = StreamController<PushMessage>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _listening = false;
  String? _uid;

  @override
  Stream<PushMessage> get foreground => _foreground.stream;

  @override
  Stream<PushMessage> get opened => _opened.stream;

  static PushMessage _toMessage(RemoteMessage message) => PushMessage(
    title: message.notification?.title ?? '',
    body: message.notification?.body ?? '',
    data: {
      for (final e in message.data.entries)
        if (e.value is String) e.key: e.value as String,
    },
  );

  /// Постоянный ID этой установки приложения — ключ документа устройства.
  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null) return existing;
    final random = Random.secure();
    final id = List.generate(
      20,
      (_) => random.nextInt(36).toRadixString(36),
    ).join();
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  Future<void> _saveToken(String uid, String token) async {
    await _db.doc('users/$uid/devices/${await _deviceId()}').set({
      'token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    _subscriptions
      ..add(
        FirebaseMessaging.onMessage.listen(
          (m) => _foreground.add(_toMessage(m)),
        ),
      )
      ..add(
        FirebaseMessaging.onMessageOpenedApp.listen(
          (m) => _opened.add(_toMessage(m)),
        ),
      )
      ..add(
        _messaging.onTokenRefresh.listen((token) {
          final uid = _uid;
          if (uid != null) unawaited(_saveToken(uid, token).catchError(_log));
        }),
      );
  }

  static void _log(Object error) => debugPrint('Push: $error');

  @override
  Future<void> start(String uid) async {
    _uid = uid;
    _listen();
    try {
      await _messaging.requestPermission();
      // Приложение открыли тапом по уведомлению, когда оно было закрыто.
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _opened.add(_toMessage(initial));

      final token = await _messaging.getToken();
      if (token != null) await _saveToken(uid, token);
    } on Object catch (error) {
      // Нет Google Play, эмуляторы Firebase без FCM, нет сети — приложение
      // работает и без push: история уведомлений всё равно видна.
      _log(error);
    }
  }

  @override
  Future<void> stop(String uid) async {
    _uid = null;
    try {
      await _db.doc('users/$uid/devices/${await _deviceId()}').delete();
      await _messaging.deleteToken();
    } on Object catch (error) {
      _log(error);
    }
  }
}

/// Firebase не подключён: push нет.
class UnavailablePushService implements PushService {
  const UnavailablePushService();

  @override
  Future<void> start(String uid) async {}

  @override
  Future<void> stop(String uid) async {}

  @override
  Stream<PushMessage> get foreground => const Stream.empty();

  @override
  Stream<PushMessage> get opened => const Stream.empty();
}
