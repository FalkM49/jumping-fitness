import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/services/theme_mode_storage.dart';
import 'package:jumping_fitness/theme/theme_mode_controller.dart';

void main() {
  group('ThemeModeController', () {
    test('по умолчанию — «Как в системе»', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeControllerProvider), ThemeMode.system);
    });

    test('стартует с сохранённого значения', () {
      final container = ProviderContainer(
        overrides: [initialThemeModeProvider.overrideWithValue(ThemeMode.dark)],
      );
      addTearDown(container.dispose);

      expect(container.read(themeModeControllerProvider), ThemeMode.dark);
    });

    test('переключает тему и сохраняет выбор', () async {
      final storage = InMemoryThemeModeStorage();
      final container = ProviderContainer(
        overrides: [themeModeStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      await container
          .read(themeModeControllerProvider.notifier)
          .setThemeMode(ThemeMode.light);

      expect(container.read(themeModeControllerProvider), ThemeMode.light);
      expect(storage.value, ThemeMode.light);
    });
  });

  group('themeModeFromName', () {
    test('распознаёт все сохранённые значения', () {
      for (final mode in ThemeMode.values) {
        expect(themeModeFromName(mode.name), mode);
      }
    });

    test('пустое или неизвестное значение → «Как в системе»', () {
      expect(themeModeFromName(null), ThemeMode.system);
      expect(themeModeFromName(''), ThemeMode.system);
      expect(themeModeFromName('purple'), ThemeMode.system);
    });
  });

  test('подписи переключателя совпадают с ТЗ 11.1', () {
    expect(ThemeMode.light.label, 'Светлая');
    expect(ThemeMode.dark.label, 'Тёмная');
    expect(ThemeMode.system.label, 'Как в системе');
  });
}
