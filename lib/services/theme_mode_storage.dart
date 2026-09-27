import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Где хранится выбор темы. Интерфейс нужен, чтобы в тестах подставлять
/// хранилище в памяти вместо настоящего SharedPreferences.
abstract interface class ThemeModeStorage {
  Future<ThemeMode> load();
  Future<void> save(ThemeMode mode);
}

/// Локальное хранение выбора темы на устройстве (ТЗ 11.1).
class SharedPrefsThemeModeStorage implements ThemeModeStorage {
  SharedPrefsThemeModeStorage([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const String _key = 'theme_mode';

  final SharedPreferencesAsync _prefs;

  @override
  Future<ThemeMode> load() async {
    try {
      return themeModeFromName(await _prefs.getString(_key));
    } on Exception catch (error) {
      // Повреждённое или недоступное хранилище не должно ронять запуск —
      // возвращаемся к значению по умолчанию «Как в системе».
      debugPrint('Не удалось прочитать выбор темы: $error');
      return ThemeMode.system;
    }
  }

  @override
  Future<void> save(ThemeMode mode) => _prefs.setString(_key, mode.name);
}

/// Хранилище в памяти — для тестов и для запуска без платформенных плагинов.
class InMemoryThemeModeStorage implements ThemeModeStorage {
  InMemoryThemeModeStorage([this.value = ThemeMode.system]);

  ThemeMode value;

  @override
  Future<ThemeMode> load() async => value;

  @override
  Future<void> save(ThemeMode mode) async => value = mode;
}

/// Разбор сохранённого значения. Неизвестное или пустое → «Как в системе»
/// (значение по умолчанию по ТЗ 11.1).
ThemeMode themeModeFromName(String? name) {
  for (final mode in ThemeMode.values) {
    if (mode.name == name) return mode;
  }
  return ThemeMode.system;
}
