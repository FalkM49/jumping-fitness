import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/theme_mode_storage.dart';

/// Хранилище выбора темы. Настоящая реализация подставляется в `main.dart`
/// через `ProviderScope(overrides: ...)`.
final themeModeStorageProvider = Provider<ThemeModeStorage>(
  (ref) => InMemoryThemeModeStorage(),
);

/// Выбор темы, прочитанный с диска ДО запуска приложения — чтобы при старте
/// не было мигания светлой темы перед тёмной.
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

/// Текущий режим темы: «Светлая» / «Тёмная» / «Как в системе».
final themeModeControllerProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  /// Переключает тему сразу, затем сохраняет выбор на устройстве.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await ref.read(themeModeStorageProvider).save(mode);
  }
}

/// Подписи вариантов для экрана настроек (ТЗ 11.1).
extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
    ThemeMode.light => 'Светлая',
    ThemeMode.dark => 'Тёмная',
    ThemeMode.system => 'Как в системе',
  };
}
