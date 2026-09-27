import 'dart:async';
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

/// Разрешение на уведомления на этом устройстве.
enum PushPermission {
  granted,

  /// Ещё не спрашивали. В браузере спросить можно только по нажатию.
  notAsked,

  /// Запрещено — включается только в настройках телефона или браузера.
  denied,

  /// Браузер не умеет push. На iPhone — пока сайт не добавлен
  /// на экран «Домой» (iOS 16.4+).
  unsupported,
}

/// Публичный ключ веб-push (VAPID): Firebase Console → Project settings →
/// Cloud Messaging → Web Push certificates. Не секрет. Другой ключ при
/// сборке: `--dart-define=WEB_PUSH_VAPID_KEY=…`.
const String webPushVapidKey = String.fromEnvironment(
  'WEB_PUSH_VAPID_KEY',
  defaultValue:
      'BMrT8JgOq7dnAuE-In9H3vhlC-VMz_fmVcLsAGH-1FkD6fySK27Km0O-kZoRpuXGr-39OJe7D5crF-Caxiloms8',
);

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

  /// Можно ли сейчас получать push на этом устройстве.
  Future<PushPermission> permission();

  /// Спросить разрешение и включить push. В браузере вызывать только
  /// по нажатию кнопки — иначе Safari не покажет запрос. 	rue — включено.
  Future<bool> enable(String uid);
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
      'platform': kIsWeb
          ? 'web'
          : defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : 'android',
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
      if (kIsWeb) {
        // В браузере запрос разрешения без нажатия Safari отклонит —
        // спрашиваем по кнопке (enable). Если уже разрешено — просто токен.
        if (await permission() == PushPermission.granted) {
          await _registerToken(uid);
        }
        return;
      }
      await _messaging.requestPermission();
      // Приложение открыли тапом по уведомлению, когда оно было закрыто.
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _opened.add(_toMessage(initial));
      await _registerToken(uid);
    } on Object catch (error) {
      // Нет Google Play, эмуляторы Firebase без FCM, нет сети — приложение
      // работает и без push: история уведомлений всё равно видна.
      _log(error);
    }
  }

  Future<void> _registerToken(String uid) async {
    final token = await _messaging.getToken(
      vapidKey: kIsWeb && webPushVapidKey.isNotEmpty ? webPushVapidKey : null,
    );
    if (token != null) await _saveToken(uid, token);
  }

  @override
  Future<PushPermission> permission() async {
    try {
      if (kIsWeb && !await _messaging.isSupported()) {
        return PushPermission.unsupported;
      }
      final settings = await _messaging.getNotificationSettings();
      return switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushPermission.granted,
        AuthorizationStatus.denied ||
        AuthorizationStatus.deniedPermanently => PushPermission.denied,
        AuthorizationStatus.notDetermined => PushPermission.notAsked,
      };
    } on Object catch (error) {
      _log(error);
      return PushPermission.unsupported;
    }
  }

  @override
  Future<bool> enable(String uid) async {
    try {
      final settings = await _messaging.requestPermission();
      final status = settings.authorizationStatus;
      if (status != AuthorizationStatus.authorized &&
          status != AuthorizationStatus.provisional) {
        return false;
      }
      await _registerToken(uid);
      return true;
    } on Object catch (error) {
      _log(error);
      return false;
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

  @override
  Future<PushPermission> permission() async => PushPermission.unsupported;

  @override
  Future<bool> enable(String uid) async => false;
}
