import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/firebase_bootstrap.dart';
import 'services/theme_mode_storage.dart';
import 'theme/theme_mode_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Выбор темы читаем до первого кадра, чтобы не было мигания
  // светлой темы у тех, кто выбрал тёмную.
  final themeStorage = SharedPrefsThemeModeStorage();
  final initialThemeMode = await themeStorage.load();

  // До этапа 8 вернёт notConfigured — каркас работает и без Firebase.
  final firebaseStatus = await FirebaseBootstrap.initialize();

  runApp(
    ProviderScope(
      overrides: [
        themeModeStorageProvider.overrideWithValue(themeStorage),
        initialThemeModeProvider.overrideWithValue(initialThemeMode),
        firebaseStatusProvider.overrideWithValue(firebaseStatus),
      ],
      child: const JumpingFitnessApp(),
    ),
  );
}
