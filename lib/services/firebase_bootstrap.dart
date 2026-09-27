import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase_options.dart';
import 'cloud_functions.dart';

/// Состояние подключения к Firebase после запуска.
enum FirebaseStatus {
  /// Firebase инициализирован, можно пользоваться сервисами.
  ready,

  /// `firebase_options.dart` ещё плейсхолдер (до этапа 8).
  notConfigured,

  /// Конфигурация есть, но инициализация не удалась.
  failed,
}

/// Результат инициализации — подставляется в `main.dart`.
/// Сервисы проверяют его, прежде чем обращаться к Firebase.
final firebaseStatusProvider = Provider<FirebaseStatus>(
  (ref) => FirebaseStatus.notConfigured,
);

/// Локальные эмуляторы Firebase вместо настоящего проекта:
///
///   flutter run --dart-define=USE_FIREBASE_EMULATORS=true
///
/// Эмуляторы запускаются из папки functions: `npm run emulators`.
/// SMS не отправляются — код для входа показывает `npm run dev:codes`.
const bool useFirebaseEmulators = bool.fromEnvironment(
  'USE_FIREBASE_EMULATORS',
);

/// Адрес компьютера с эмуляторами. `localhost` на Android-эмуляторе
/// плагины Firebase сами заменяют на 10.0.2.2; для телефона по Wi-Fi —
/// `--dart-define=FIREBASE_EMULATOR_HOST=192.168.x.x`.
const String firebaseEmulatorHost = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
  defaultValue: 'localhost',
);

abstract final class FirebaseBootstrap {
  /// Проект эмуляторов: префикс `demo-` не даёт обратиться к настоящему
  /// Firebase даже по ошибке.
  static const FirebaseOptions emulatorOptions = FirebaseOptions(
    // Не настоящий ключ, но в формате Google API key (AIza + 35 символов):
    // Android-плагин Functions проверяет формат даже для эмулятора.
    apiKey: 'AIzaSyDemoKeyForLocalEmulatorsOnly00000',
    appId: '1:000000000000:android:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-jumping-fitness',
  );

  static Future<FirebaseStatus> initialize() async {
    if (useFirebaseEmulators) return _initializeEmulators();
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return FirebaseStatus.ready;
    } on UnsupportedError catch (error) {
      // Плейсхолдер или платформа, не добавленная в `flutterfire configure`.
      debugPrint('Firebase: ${error.message}');
      return FirebaseStatus.notConfigured;
    } on FirebaseException catch (error) {
      debugPrint('Firebase: ошибка инициализации — ${error.message}');
      return FirebaseStatus.failed;
    }
  }

  static Future<FirebaseStatus> _initializeEmulators() async {
    try {
      await Firebase.initializeApp(options: emulatorOptions);
      await FirebaseAuth.instance.useAuthEmulator(firebaseEmulatorHost, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(
        firebaseEmulatorHost,
        8080,
      );
      regionalFunctions().useFunctionsEmulator(firebaseEmulatorHost, 5001);
      debugPrint('Firebase: локальные эмуляторы ($firebaseEmulatorHost)');
      return FirebaseStatus.ready;
    } on FirebaseException catch (error) {
      debugPrint('Firebase: эмуляторы недоступны — ${error.message}');
      return FirebaseStatus.failed;
    }
  }
}
