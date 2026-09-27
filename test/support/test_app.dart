import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jumping_fitness/app.dart';
import 'package:jumping_fitness/services/backend_providers.dart';
import 'package:jumping_fitness/services/firebase_bootstrap.dart';
import 'package:jumping_fitness/services/theme_mode_storage.dart';
import 'package:jumping_fitness/theme/app_theme.dart';
import 'package:jumping_fitness/theme/app_typography.dart';
import 'package:jumping_fitness/theme/theme_mode_controller.dart';

import 'fake_push.dart';
import 'fake_studio.dart';
import 'fakes.dart';

/// «Сейчас» во всех тестах экранов: понедельник 28 сентября 2026,
/// 12:00 по Москве (09:00 UTC) — день тренировок по расписанию.
final testNow = DateTime.utc(2026, 9, 28, 9);

/// Приложение целиком, но офлайн: шрифты без сети, Firebase — подделки.
/// Без [auth] и [backend] используются заглушки «сервер не подключён».
Widget buildTestApp({
  FakeAuthRepository? auth,
  FakeBackend? backend,
  FakeStudio? studio,
  FakePush? push,
  FakeNotifications? notifications,
  InMemoryThemeModeStorage? themeStorage,
  DateTime? now,
}) {
  final storage = themeStorage ?? InMemoryThemeModeStorage();
  final connected = auth != null && backend != null;
  final studioFake = studio ?? FakeStudio(uid: auth?.current?.uid ?? '');
  final clock = now ?? testNow;

  return ProviderScope(
    overrides: [
      lightThemeProvider.overrideWithValue(
        AppTheme.light(font: plainFontApplier),
      ),
      darkThemeProvider.overrideWithValue(
        AppTheme.dark(font: plainFontApplier),
      ),
      themeModeStorageProvider.overrideWithValue(storage),
      initialThemeModeProvider.overrideWithValue(storage.value),
      firebaseStatusProvider.overrideWithValue(
        connected ? FirebaseStatus.ready : FirebaseStatus.notConfigured,
      ),
      clockProvider.overrideWithValue(() => clock),
      if (auth != null) authRepositoryProvider.overrideWithValue(auth),
      if (backend != null) ...[
        userRepositoryProvider.overrideWithValue(backend),
        trainerRequestsRepositoryProvider.overrideWithValue(backend),
      ],
      if (connected) ...[
        studioRepositoryProvider.overrideWithValue(studioFake),
        studioFunctionsProvider.overrideWithValue(studioFake),
        pushServiceProvider.overrideWithValue(push ?? FakePush()),
        notificationsRepositoryProvider.overrideWithValue(
          notifications ?? FakeNotifications(),
        ),
      ],
    ],
    child: const JumpingFitnessApp(),
  );
}
